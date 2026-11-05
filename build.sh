#!/bin/bash
# Build a Xiaomi RA82 (international) firmware for Xiaomi CR881x.
#
# Userspace (web UI, mesh, Mi WiFi app) comes from the official RA82 image,
# the hardware layer (kernel, modules, WiFi/NSS firmware, YT9215 tools)
# comes from a CR8818 stock image. That image may be your own mtd18 dump or,
# equivalently, the official CR8818 firmware .bin from Xiaomi's CDN: the
# downloaded 6.20.58 rootfs is byte-identical to the dump, so either works.
#
# Usage:
#   ROOT_PASSWORD='...' ./build.sh <miwifi_ra82_firmware_*.bin> <cr8818_stock> [out_dir]
#     <cr8818_stock>: a raw mtd18 dump or the official miwifi_cr8818_firmware_*.bin
#
# Optional:
#   COUNTRY=VN         nvram CountryCode set on boot when empty or CN
#   FEATURES="..."     space separated list of extras to add (default: adblock wol)
#       adblock        dnsmasq blocklist updater at /usr/sbin/adblock-update
#       wol            Wake-on-LAN sender at /usr/bin/wol
#       zerotier       ZeroTier, needs ZEROTIER_BIN=/path (see tools/build-zerotier.sh)
#       dropbear       newer dropbear, needs DROPBEAR_BIN=/path (tools/build-dropbear.sh)
#       sshfallback    stock dropbear on :2222 as an emergency SSH fallback
#                      (recommended together with dropbear, in case it fails)
#   ZEROTIER_BIN=..., DROPBEAR_BIN=...   static ARMv7 binaries for the above
#
# Always applied (device fixes, not optional): YT9215 port map, LED names,
# nvram fixups, SSH host key persistence, disabled upgrade.
#
# Needs: python3 squashfs-tools mtd-utils (ubinize) fakeroot openssl patch

set -euo pipefail

RA82_BIN=${1:?RA82 firmware .bin}
STOCK_DUMP=${2:?CR8818 stock mtd18 dump}
OUT=${3:-out}
# May be empty for a blank, OpenWrt-style passwordless first login (then set
# one with passwd). Must still be defined, so an accidental unset is caught.
: "${ROOT_PASSWORD?set ROOT_PASSWORD (use '' for a blank first-login password)}"

FEATURES=${FEATURES-adblock wol}
has_feature() { case " $FEATURES " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
for f in $FEATURES; do
	case "$f" in
	adblock|wol|zerotier|dropbear|sshfallback) ;;
	*) echo "unknown feature: $f (adblock wol zerotier dropbear sshfallback)" >&2; exit 1 ;;
	esac
done
has_feature zerotier && : "${ZEROTIER_BIN:?FEATURES has zerotier, set ZEROTIER_BIN}"
has_feature dropbear && : "${DROPBEAR_BIN:?FEATURES has dropbear, set DROPBEAR_BIN}"
if [ -z "$ROOT_PASSWORD" ] && ! has_feature dropbear; then
	echo "WARNING: empty ROOT_PASSWORD needs FEATURES=dropbear built with the" >&2
	echo "         allow-blank-root patch; the stock dropbear rejects blank" >&2
	echo "         passwords, so you would be locked out of SSH." >&2
fi
echo "==> features: ${FEATURES:-(none)}"

TOP=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

for tool in python3 unsquashfs mksquashfs ubinize fakeroot openssl patch; do
	command -v $tool >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done

echo "==> Unpacking"
python3 -I "$TOP/tools/xiaomi_fw.py" hdr1 "$RA82_BIN" "$WORK/ra82.ubi"
python3 -I "$TOP/tools/xiaomi_fw.py" ubi "$WORK/ra82.ubi" "$WORK/ra82"
# The CR8818 hardware layer is either a raw mtd18 dump (UBI straight away) or
# the official CR8818 firmware (HDR1 wrapped); unwrap the header when present.
if head -c4 "$STOCK_DUMP" | cmp -s - <(printf 'HDR1'); then
	python3 -I "$TOP/tools/xiaomi_fw.py" hdr1 "$STOCK_DUMP" "$WORK/stock.ubi"
	python3 -I "$TOP/tools/xiaomi_fw.py" ubi "$WORK/stock.ubi" "$WORK/stock"
else
	python3 -I "$TOP/tools/xiaomi_fw.py" ubi "$STOCK_DUMP" "$WORK/stock"
fi

KERNEL="$WORK/stock/0_kernel.bin"
head -c 4 "$KERNEL" | cmp -s - <(printf '\xd0\x0d\xfe\xed') ||
	{ echo "stock kernel volume is not a FIT image" >&2; exit 1; }

# Everything touching the rootfs runs inside one fakeroot session, so that
# ownership and modes survive the unsquashfs/mksquashfs round trip.
export TOP WORK ROOT_PASSWORD
export COUNTRY=${COUNTRY:-}
export FEATURES
export ZEROTIER_BIN=${ZEROTIER_BIN:-}
export DROPBEAR_BIN=${DROPBEAR_BIN:-}
fakeroot bash -euo pipefail <<'EOF'
R=$WORK/rootfs
S=$WORK/stockfs
unsquashfs -q -d "$R" "$WORK/ra82/1_ubi_rootfs.bin"
unsquashfs -q -d "$S" "$WORK/stock/1_ubi_rootfs.bin"

grep -q "HARDWARE 'RA82'" "$R/usr/share/xiaoqiang/xiaoqiang_version" ||
	{ echo "not an RA82 firmware" >&2; exit 1; }
grep -q "HARDWARE 'CR8818'" "$S/usr/share/xiaoqiang/xiaoqiang_version" ||
	{ echo "stock dump is not a CR8818 firmware" >&2; exit 1; }

echo "==> Hardware layer from CR8818 stock"
# Kernel modules must match the stock kernel
rm -rf "$R/lib/modules"
cp -a "$S/lib/modules" "$R/lib/modules"

# WiFi (IPQ5018 + QCN6122) and NSS firmware
rm -rf "$R/lib/firmware/IPQ5018" "$R/lib/firmware/qcn6122"
cp -a "$S/lib/firmware/IPQ5018" "$S/lib/firmware/qcn6122" "$R/lib/firmware/"
cp -a "$S"/lib/firmware/qca-nss0*.bin "$R/lib/firmware/"
cp -a "$S/lib/read_caldata_to_fs.sh" "$R/lib/"

# YT9215 switch tool
cp -a "$S/usr/sbin/switch_ctl" "$R/usr/sbin/"

# Module autoload lists: drop modules the CR8818 kernel does not have,
# take the switch/NSS/netfilter entries from stock
cp -a "$S/etc/modules-boot.d/." "$R/etc/modules-boot.d/"
for f in 09-crypto-gf128 09-crypto-xts 20-lib-crc16 30-dm 30-fs-ext4 30-loop \
	 43-ip6tables-extra 43-ipt-nat6 77-ipaccount2; do
	rm -f "$R/etc/modules.d/$f" "$R/etc/modules-boot.d/$f"
done
# 52-qca-mcs: ecm depends on qca-mcs (mc_bridge_* symbols); the RA82
# userspace autoloads the rest of the NSS stack but not qca-mcs, so ECM/NSS
# acceleration failed to load on boot
for f in 52-qca-mcs 57-yt-9215s-driver 77-ipaccount3 88-ip6tables-extra 88-ipt-nat6; do
	cp -a "$S/etc/modules.d/$f" "$R/etc/modules.d/"
done

# LVM/ext4 and the LUKS-encrypted config volume need loop/dm-crypt/ext4
# modules missing from the CR8818 kernel
rm -f "$R/etc/init.d/lvm2" "$R"/etc/rc.d/*lvm2
rm -f "$R/lib/preinit/89_mount_sec_cfg"

# Router picture for the CR881x colour variant (bdata color=101)
for d in icons topograph; do
	for s in "" _on; do
		cp -a "$R/www/xiaoqiang/web/img/$d/router_ra82_100$s.png" \
		      "$R/www/xiaoqiang/web/img/$d/router_ra82_101$s.png"
	done
done

echo "==> Patches"
for p in "$TOP"/patches/*.patch; do
	echo "    $(basename "$p")"
	patch -d "$R" -p1 -s --no-backup-if-mismatch < "$p"
done

echo "==> nvram fixups (country: ${COUNTRY:-unchanged})"
if [ -n "$COUNTRY" ]; then
	grep -q "^config mapping $COUNTRY\$" "$R/etc/config/country_mapping" ||
		{ echo "unknown COUNTRY $COUNTRY (see /etc/config/country_mapping)" >&2; exit 1; }
fi
sed "s/@COUNTRY@/$COUNTRY/" "$TOP/files/33_cr881x_nvram" > "$R/lib/preinit/33_cr881x_nvram"
chmod 644 "$R/lib/preinit/33_cr881x_nvram"

if [ -n "$ROOT_PASSWORD" ]; then
	echo "==> root password"
	hash=$(openssl passwd -1 "$ROOT_PASSWORD")
	sed -i "s|^root:[^:]*:|root:${hash}:|" "$R/etc/shadow"
else
	echo "==> root password: BLANK (passwordless first SSH; run passwd after)"
	sed -i "s|^root:[^:]*:|root::|" "$R/etc/shadow"
fi
chmod 600 "$R/etc/shadow"

has_feature() { case " $FEATURES " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

if has_feature zerotier; then
	echo "==> ZeroTier"
	install -m 0755 "$ZEROTIER_BIN" "$R/usr/bin/zerotier-one"
	ln -sf zerotier-one "$R/usr/bin/zerotier-cli"
	ln -sf zerotier-one "$R/usr/bin/zerotier-idtool"
	install -m 0755 "$TOP/files/zerotier.init" "$R/etc/init.d/zerotier"
	ln -sf ../init.d/zerotier "$R/etc/rc.d/S90zerotier"
fi

if has_feature sshfallback; then
	echo "==> ssh fallback (stock dropbear on :2222)"
	# keep the firmware's original dropbear before it is replaced
	cp -a "$R/usr/sbin/dropbear" "$R/usr/sbin/dropbear-stock"
	install -m 0755 "$TOP/files/dropbear-fallback.init" "$R/etc/init.d/dropbear-fallback"
	ln -sf ../init.d/dropbear-fallback "$R/etc/rc.d/S51dropbear-fallback"
fi

if has_feature dropbear; then
	echo "==> dropbear"
	# dbclient, dropbearkey, scp and ssh are symlinks to it
	install -m 0755 "$DROPBEAR_BIN" "$R/usr/sbin/dropbear"
fi

if has_feature adblock; then
	echo "==> adblock"
	# dnsmasq blocklist updater (list lives in /data, run on demand)
	install -m 0755 "$TOP/files/adblock-update.sh" "$R/usr/sbin/adblock-update"
fi

if has_feature wol; then
	echo "==> wol"
	install -m 0755 "$TOP/files/wol" "$R/usr/bin/wol"
fi

echo "==> squashfs"
mksquashfs "$R" "$WORK/rootfs.squashfs" -comp xz -b 262144 -noappend -all-root -quiet
EOF

echo "==> UBI"
cat > "$WORK/ubinize.cfg" <<EOF
[kernel]
mode=ubi
image=$KERNEL
vol_id=0
vol_type=dynamic
vol_name=kernel

[ubi_rootfs]
mode=ubi
image=$WORK/rootfs.squashfs
vol_id=1
vol_type=dynamic
vol_name=ubi_rootfs
EOF
VER=$(sed -n "s/.*option ROM '\(.*\)'/\1/p" "$WORK/rootfs/usr/share/xiaoqiang/xiaoqiang_version" 2>/dev/null || true)
NAME="cr881x-ra82-${VER:-unknown}-mod"
ubinize -o "$OUT/$NAME.ubi" -p 128KiB -m 2048 -O 2048 "$WORK/ubinize.cfg"

SIZE=$(stat -c %s "$OUT/$NAME.ubi")
LIMIT=$((30 * 1024 * 1024))
[ "$SIZE" -le "$LIMIT" ] || { echo "image too big: $SIZE > $LIMIT" >&2; exit 1; }
(cd "$OUT" && sha256sum "$NAME.ubi" > "$NAME.ubi.sha256")
echo "==> $OUT/$NAME.ubi ($SIZE bytes)"
