# Xiaomi CR881x – RA82 international firmware

*[Tiếng Việt](README.md)*

Scripts that rebuild the **Xiaomi Mesh System AX3000 (RA82) international**
firmware for the **Xiaomi CR881x** (CR8808 / CR8818, CMCC carrier variant):
Xiaomi web UI, mesh, international Mi WiFi / Xiaomi Home app, NSS offload.

* Userspace (web, mesh, app) comes from the **official** RA82 firmware image.
* The hardware layer (kernel, modules, WiFi/NSS firmware, YT9215 switch tool)
  comes from a **CR8818 stock ROM dump** (mtd18) or, equivalently, the
  **official CR8818 firmware** from Xiaomi's CDN (the 6.20.58 rootfs is
  byte-identical to the dump).
* SSH (port 22) uses a root password set at build time; UART is left enabled.

Tested on a real CR8818: boot, switch, WiFi 2.4/5 GHz, web setup wizard.

The repo contains only scripts and patches — no Xiaomi firmware and no
per-device data (Xiaomi copyright; a dump holds the SN, MACs and factory
passwords).

## What build.sh does

| Step | Content |
|---|---|
| Kernel | `kernel` volume from the CR8818 stock ROM (FIT with the `mp03.3` config) |
| Modules | `/lib/modules` from the stock ROM (matches the kernel) |
| Firmware | `IPQ5018/WIFI_FW`, `qcn6122`, `qca-nss0*.bin`, `read_caldata_to_fs.sh` from the stock ROM |
| Switch | `switch_ctl` from the stock ROM, autoload `yt-9215s`, `qca-ssdk-nohnat`, `qca-nss-dp` |
| Removed | LVM and the LUKS config volume (`89_mount_sec_cfg`): need `loop`/`dm-crypt` modules the CR8818 kernel lacks |
| Router image | Adds `router_ra82_101*.png` for the `101` colour variant |
| Patches | See the table below |
| nvram | Preinit `33_cr881x_nvram`, runs on every boot |
| root | Password from `ROOT_PASSWORD`, `/etc/shadow` mode 600 |
| ZeroTier | Optional, if `ZEROTIER_BIN` is set |
| Dropbear | Optional, if `DROPBEAR_BIN` is set |

| Patch | Content |
|---|---|
| `10-switch-yt9215-ports.patch` | RA82 ports (LAN 1-3, WAN 4, CPU 5/6) → YT9215 (LAN 0-2, WAN 3, CPU 4/5) |
| `20-leds.patch` | LED names per the CR881x device tree (`sys_blue`/`sys_red`) |
| `30-international.patch` | Connectivity/NTP checks off Chinese servers, English login page |
| `40-disable-upgrade.patch` | Disable OTA and the web upgrade button: the official RA82 image **has no YT9215 driver** and would kill wired networking |
| `50-boot-ssh.patch` | Keep PHYs down until boot finishes, do not reset the root password, keep SSH on |
| `60-dropbear-hostkeys.patch` | SSH host keys in `/data/dropbear`, kept across reboots; `-R` generates any missing key (ed25519 with the newer dropbear) |

### CMCC nvram

nvram is shared with the CR8818 stock ROM and is overwritten by `bdata sync`
on reset, so it drifts from what the RA82 firmware expects. `33_cr881x_nvram`
fixes it on every boot:

| nvram | Symptom if missing | Fix |
|---|---|---|
| `EncryptMode` | Web login always `401 not auth` (server compares SHA1 against a SHA256 hash) | `1` |
| `CountryCode` | Runs in the `CN` region | `COUNTRY` at build time, only when empty or `CN` |
| `wl1_ssid`/`wl0_ssid` | A `CMCC-xxxx` name breaks `formatSsidName` on the setup page | `Xiaomi_XXXX`, only when `CMCC-*` |

## Build

Needs Linux/WSL with `python3 squashfs-tools mtd-utils fakeroot openssl patch`.

Dump the stock ROM on a router still running stock from mtd18:

```sh
dd if=/dev/mtd18 of=/tmp/mtd18.bin
```

Build (the country code must exist in the RA82 `/etc/config/country_mapping`):

```sh
COUNTRY=VN ROOT_PASSWORD='...' ./build.sh \
    miwifi_ra82_firmware_db06e_1.4.31_INT.bin \
    mtd18.bin \
    out
```

Output: `out/cr881x-ra82-1.4.31-mod.ubi` (~27 MB, 30 MB max) and `.sha256`.

No dump? Pass the official CR8818 firmware (HDR1) as the second argument instead;
`build.sh` unwraps the header automatically:

```sh
COUNTRY=VN ROOT_PASSWORD='...' ./build.sh \
    miwifi_ra82_firmware_db06e_1.4.31_INT.bin \
    miwifi_cr8818_firmware_4f56a_6.20.58.bin \
    out
```

### Selecting features (FEATURES)

`FEATURES` picks the optional parts baked into the image (default `adblock wol`):

| Feature | Adds | Needs |
|---|---|---|
| `adblock` | `/usr/sbin/adblock-update` (DNS blocklist) | — |
| `wol` | `/usr/bin/wol` (Wake-on-LAN) | — |
| `zerotier` | ZeroTier + its autostart service | `ZEROTIER_BIN=` |
| `dropbear` | replace dropbear with a newer one (ed25519) | `DROPBEAR_BIN=` |
| `sshfallback` | stock dropbear on port 2222 (emergency SSH) | — |

The hardware fixes (YT9215 port map, LEDs, nvram, SSH host keys, disabled
upgrade) are **always applied** and are not part of `FEATURES`.

```sh
FEATURES="adblock wol zerotier dropbear sshfallback" \
    ZEROTIER_BIN=out/zerotier-one DROPBEAR_BIN=out/dropbear \
    COUNTRY=VN ROOT_PASSWORD='...' ./build.sh <ra82.bin> <mtd18.bin> out

FEATURES= ... ./build.sh ...     # add nothing
```

### Automated build (GitHub Actions)

`.github/workflows/build.yml` builds the full-featured image on GitHub with **no
dump and no secret**: it downloads both the RA82 and CR8818 6.20.58 firmware from
Xiaomi's CDN, builds the static ARMv7 ZeroTier/dropbear binaries, generates a
random root password and writes it into the release.

* Run it from **Actions → build firmware → Run workflow** (pick `country`,
  `features`), or push a `v*` / `fw-*` tag.
* It publishes a **Release** with the `.ubi` + `.sha256` attached and the
  **default password** (SSH + web) in the notes. That password is public on a
  public repo — change it with `passwd` right after the first login.

## Flashing

The CR881x has two slots: `rootfs` (mtd18) and `rootfs_1` (mtd19). You can only
write to the slot that is **not running**. Check the running slot:

```sh
cat /proc/cmdline | grep -o "ubi.mtd=[a-z_0-9]*"
```

Copy the image with `scp -O` (dropbear has no SFTP). **Do not use
`cat file | ssh ...` in PowerShell**: `cat` is `Get-Content`, which reads the
file as text and corrupts binaries.

```sh
scp -O out/cr881x-ra82-1.4.31-mod.ubi root@192.168.31.1:/tmp/mod.ubi
```

If the router runs the old dropbear (ssh-rsa only), add
`-o HostKeyAlgorithms=+ssh-rsa`. Always verify `sha256sum /tmp/mod.ubi` against
the `.sha256` file before `ubiformat`.

Running from mtd18 (`ubi.mtd=rootfs`), write to mtd19:

```sh
ubiformat /dev/mtd19 -y -f /tmp/mod.ubi
nvram set flag_try_sys2_failed=0
nvram set flag_boot_rootfs=1
nvram set flag_last_success=1
nvram set flag_format_overlay=1
nvram commit
reboot
```

Running from mtd19 (`ubi.mtd=rootfs_1`), write to mtd18 (overwrites the stock
ROM; keep the dump to restore it):

```sh
ubiformat /dev/mtd18 -y -f /tmp/mod.ubi
nvram set flag_try_sys1_failed=0
nvram set flag_boot_rootfs=0
nvram set flag_last_success=0
nvram set flag_format_overlay=1
nvram commit
reboot
```

* U-Boot picks the slot from `flag_boot_rootfs` and `flag_last_success`; both
  flags must match. **No automatic rollback**: if the new image fails to boot
  you need UART. `flag_ota_reboot` does not change the slot.
* `flag_format_overlay=1`: both slots share the `overlay` config partition
  (mtd20, mounted at `/data`). `/etc/passwd`, `/etc/shadow`, `/etc/config`… are
  only copied from the ROM into `/data` when `/data` was just formatted.
  **Required** when switching from the CMCC stock ROM or any other firmware.
  Drop this flag only when updating from this repo's own build, to keep config.
* The format flag is consumed by whichever ROM boots next: if U-Boot still boots
  the old slot, that slot's config gets formatted.
* The first SSH after flashing warns about a changed host key:
  `ssh-keygen -R 192.168.31.1`.

Back to the stock ROM (while it is still on mtd18):

```sh
nvram set flag_boot_rootfs=0
nvram set flag_last_success=0
nvram commit
reboot
```

## ZeroTier

The CR8818 kernel has TUN built in, so only the binary is needed. The firmware
uses the old musl of OpenWrt 18.06, so build `zerotier-one` statically:

```sh
sudo apt install g++-arm-linux-gnueabihf
tools/build-zerotier.sh 1.14.2 out
ZEROTIER_BIN=out/zerotier-one COUNTRY=VN ROOT_PASSWORD='...' ./build.sh <ra82.bin> <mtd18.bin> out
```

The identity and joined networks live in `/data/zerotier`: kept across reboots,
lost on a `/data` format or reset (the router then gets a new node ID and must
be re-authorized).

### ZeroTier setup

1. Create a network on [ZeroTier Central](https://my.zerotier.com) and note the
   **Network ID** (16 hex chars). The examples below use the ZeroTier range
   `10.147.17.0/24` and the router LAN `192.168.31.0/24`.

2. On the router (SSH), check the service and join:

   ```sh
   zerotier-cli info                    # 200 info <node id> 1.14.2 ONLINE
   zerotier-cli join <network id>
   ```

   If it reports no connection: `/etc/init.d/zerotier restart`, wait a few seconds.

3. On ZeroTier Central, **Members**: tick **Auth** for the router's node ID and
   give it a fixed IP, e.g. `10.147.17.1`.

4. Check on the router:

   ```sh
   zerotier-cli listnetworks            # status OK, interface ztXXXXXXXX, IP
   ip addr show | grep -A2 " zt"
   ```

5. Open the firewall for the ZeroTier interface. The Xiaomi firewall rebuilds
   its rules on every reload, so the rule must live in an `include` script:

   ```sh
   cat > /data/zerotier/firewall.sh <<'EOF'
   #!/bin/sh
   # Reach the router and the LAN from the ZeroTier network
   for rule in "INPUT -i zt+" "FORWARD -i zt+" "FORWARD -o zt+"; do
       iptables -C $rule -j ACCEPT 2>/dev/null || iptables -I $rule -j ACCEPT
   done
   EOF
   chmod +x /data/zerotier/firewall.sh

   uci set firewall.zerotier=include
   uci set firewall.zerotier.path=/data/zerotier/firewall.sh
   uci commit firewall
   /data/zerotier/firewall.sh
   ```

   To reach only the router itself (web, SSH), keep the `INPUT` line and drop the
   two `FORWARD` lines.

6. Reach LAN hosts (optional): on ZeroTier Central, **Managed Routes**, add
   `192.168.31.0/24` via `10.147.17.1` (the router's ZeroTier IP). Other members
   can then reach `192.168.31.x`.

   Instead of a route you can NAT (LAN hosts see the connection coming from the
   router's IP) by adding to `firewall.sh`:

   ```sh
   iptables -t nat -C POSTROUTING -s 10.147.17.0/24 -o br-lan -j MASQUERADE 2>/dev/null ||
       iptables -t nat -I POSTROUTING -s 10.147.17.0/24 -o br-lan -j MASQUERADE
   ```

7. Test from another ZeroTier member: `ping 10.147.17.1`, open
   `http://10.147.17.1`, then `ping 192.168.31.x` if you did step 6.

Leave a network: `zerotier-cli leave <network id>`. Disable entirely
(`/etc/rc.d` is read-only, so `disable` does not work):
`touch /data/zerotier/disabled; /etc/init.d/zerotier stop`.
Re-enable: `rm /data/zerotier/disabled; /etc/init.d/zerotier start`.

For images built before `/var/lib/zerotier-one` → `/data/zerotier`, run
`ln -sfn /data/zerotier /var/lib/zerotier-one` (lost on reboot) or use
`zerotier-cli -D/data/zerotier ...`.

The firewall rules in steps 5–6 have not been tested on real hardware; if it
does not work, check `iptables -S | grep zt` and `ip route`.

## SSH

The firmware's dropbear 2017.75 only offers an `ssh-rsa` host key; OpenSSH ≥ 8.8
refuses it: `no matching host key type found. Their offer: ssh-rsa`. Replace it
with a newer dropbear (with `ed25519`, `rsa-sha2-256`), built statically against
musl. Two ways, both tested on the router:

```sh
# Quick (a few minutes): Ubuntu's ARM gcc + musl built from source
sudo apt install gcc-arm-linux-gnueabihf
tools/build-dropbear.sh 2026.94 out

# Or an existing musl toolchain, e.g. OpenWrt target ipq40xx
# (Cortex-A7, runs on the IPQ5018 Cortex-A53 in 32-bit mode):
#   in the OpenWrt tree: make tools/install toolchain/install
tools/build-dropbear.sh --toolchain \
    <openwrt>/staging_dir/toolchain-arm_cortex-a7+neon-vfpv4_gcc-*_musl_eabi \
    2026.94 out

DROPBEAR_BIN=out/dropbear ZEROTIER_BIN=out/zerotier-one COUNTRY=VN ROOT_PASSWORD='...' ./build.sh <ra82.bin> <mtd18.bin> out
```

Pass a `dropbear-*.tar.bz2` tarball path instead of `2026.94` to skip the
download; likewise `MUSL=<version|tarball>` for musl (default 1.2.6).

The dropbear in the image is a multi-call binary: `dropbear`, `ssh`/`dbclient`,
`scp`, `dropbearkey` all point at `/usr/sbin/dropbear`. Tested (v2026.94).

`build-dropbear.sh` applies OpenWrt's patch
(`files/dropbear-allow-blank-root-password.patch`) that lets root log in with a
blank password (see below); the patch is harmless when root has a password.

Without replacing dropbear, add to the client's `~/.ssh/config`:

```
Host 192.168.31.1
    HostKeyAlgorithms +ssh-rsa
    PubkeyAcceptedAlgorithms +ssh-rsa
```

Host keys live in `/data/dropbear` (bind-mounted over `/etc/dropbear`,
`60-dropbear-hostkeys.patch`), so they do not change across reboots; only on a
`/data` format or reset.

### Blank root password (OpenWrt-style)

Dropbear rejects any blank password on the *password* path; OpenWrt patches the
*none* path so a blank-password root still gets in (that is how modern OpenWrt
offers passwordless first SSH, replacing telnet). That patch is in
`build-dropbear.sh`.

Build the image with **`ROOT_PASSWORD=''`** → `/etc/shadow` gets `root::`. It
needs **`FEATURES=dropbear`** (the patched dropbear); the stock 2017.75 has no
patch and still rejects it. First SSH is **passwordless**:

```sh
FEATURES="adblock wol dropbear sshfallback" DROPBEAR_BIN=out/dropbear \
    COUNTRY=VN ROOT_PASSWORD='' ./build.sh <ra82.bin> <mtd18.bin> out
# after boot:
ssh root@192.168.31.1        # no password prompt
passwd                        # SET a password right away
```

⚠️ Until you run `passwd`, anyone on the LAN can SSH in as root with no password
(just like a freshly flashed OpenWrt). The fallback on port 2222 is the stock
dropbear (no patch), so blank does not work there — use it only after setting a
password.

### Emergency SSH (no UART)

When using the newer dropbear, add `sshfallback`: the **old** dropbear (2017.75)
runs in parallel on port **2222**, independent of the main one on 22. If the new
dropbear fails to start after flashing, you can still get in and fix it without
UART:

```sh
ssh -o HostKeyAlgorithms=+ssh-rsa -p 2222 root@192.168.31.1
```

Telnet does not work on this firmware (busybox telnetd exits 255), so this is
the replacement safety net, and it stays encrypted. Once the main dropbear is
known good you can disable it:
`/etc/init.d/dropbear-fallback disable; /etc/init.d/dropbear-fallback stop`.

## Adblock (DNS sinkhole)

The firmware already ships `dnsmasq`, so blocking ads at the DNS level like
Pi-hole needs nothing heavy. `/usr/sbin/adblock-update` (in the image) fetches a
hosts-format blocklist and writes `/data/dnsmasq.d/adblock.conf`
(`address=/domain/#`, which blocks subdomains too).

One-time setup on the router:

```sh
uci set dhcp.@dnsmasq[0].confdir=/data/dnsmasq.d
uci commit dhcp
adblock-update
```

`adblock-update` downloads (with a timeout), converts, then restarts dnsmasq.
The source list is `/data/adblock.lists` (one URL per line; default StevenBlack
~77k domains). In Vietnam `raw.githubusercontent.com` is often slow/stalls —
switch to the jsDelivr CDN:

```sh
echo 'https://cdn.jsdelivr.net/gh/StevenBlack/hosts@master/hosts' > /data/adblock.lists
```

Refresh on a schedule with cron:

```sh
echo '0 5 * * 0 /usr/sbin/adblock-update >/tmp/adblock.log 2>&1' >> /etc/crontabs/root
/etc/init.d/cron enable; /etc/init.d/cron restart
```

Disable: `uci delete dhcp.@dnsmasq[0].confdir; uci commit dhcp; /etc/init.d/dnsmasq restart`.
Everything lives in `/data`, lost on a `/data` format or reset (redo the steps).

You can also generate the file on a PC and `scp -O` it into `/data/dnsmasq.d/`:
`tools/adblock-gen.sh out/adblock.conf`.

## Patching files on the router without reflashing

The rootfs is a read-only squashfs. You can bind-mount a modified copy kept in
`/data` over the original file, re-applied on every boot through a firewall
`include` (`/etc/config` lives in `/data`):

```sh
uci set firewall.my_patch=include
uci set firewall.my_patch.path=/data/patch/apply.sh
uci commit firewall
```

`apply.sh` must check before it mounts, since a firewall reload runs it again.

## Tools

* `tools/xiaomi_fw.py hdr1 <miwifi_*.bin> <out.ubi>`: extract the UBI image from a Xiaomi firmware file
* `tools/xiaomi_fw.py ubi <ubi|mtd dump> <dir>`: extract UBI volumes
* `tools/adblock-gen.sh [out.conf] [url ...]`: build a dnsmasq blocklist from hosts lists
* `tools/build-zerotier.sh`, `tools/build-dropbear.sh`: build static ARMv7 binaries
