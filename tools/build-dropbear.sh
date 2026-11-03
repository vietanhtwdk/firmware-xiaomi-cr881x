#!/bin/bash
# Build a static ARMv7 dropbear (multi-call: dropbear, dbclient, dropbearkey,
# scp). The stock dropbear 2017.75 only offers ssh-rsa, which OpenSSH >= 8.8
# refuses by default; newer dropbear adds ed25519 and rsa-sha2-256.
#
# It has to be linked against musl: getpwnam()/crypt() do not work from a
# static glibc binary on the musl based firmware. Two ways:
#
#   quick (default): Ubuntu's gcc-arm-linux-gnueabihf plus musl built from
#     source and used through its musl-gcc wrapper. Takes a couple of minutes.
#   toolchain: a real musl cross toolchain, e.g. OpenWrt ipq40xx
#     (make toolchain/install), via --toolchain.
#
# Both were tested on the router (dropbear 2026.94).
#
# Usage: tools/build-dropbear.sh [--toolchain <dir>] <dropbear version|tarball> [out_dir]
#   toolchain dir: .../staging_dir/toolchain-arm_cortex-a7+neon-vfpv4_gcc-*_musl_eabi
#   MUSL=<version|tarball> selects musl for the quick build (default 1.2.6)
#
# Needs: curl make, and gcc-arm-linux-gnueabihf for the quick build

set -euo pipefail

TC=
if [ "${1:-}" = "--toolchain" ]; then
	TC=${2:?toolchain dir}
	shift 2
fi
SRC=${1:?dropbear version or tarball}
OUT=${2:-out}
MUSL=${MUSL:-1.2.6}
ARCH="-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard"
TOP=$(cd "$(dirname "$0")/.." && pwd)

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

fetch() { # <version|tarball> <url pattern with @V@> <tar flags>
	if [ -f "$1" ]; then
		tar "$3" "$1" -C "$WORK"
	else
		curl -sfL "${2//@V@/$1}" | tar "$3" - -C "$WORK"
	fi
}

if [ -n "$TC" ]; then
	CC=$(ls "$TC"/bin/*-linux-musl*-gcc 2>/dev/null | head -1)
	[ -x "$CC" ] || { echo "no musl gcc in $TC/bin" >&2; exit 1; }
	CROSS=$(basename "${CC%-gcc}")
	export PATH="$TC/bin:$PATH" STAGING_DIR="$TC"
	CFLAGS="-Os"
	LIBS=
else
	CROSS=arm-linux-gnueabihf
	command -v $CROSS-gcc >/dev/null || {
		echo "missing $CROSS-gcc (apt install gcc-arm-linux-gnueabihf)" >&2
		exit 1
	}
	fetch "$MUSL" "https://musl.libc.org/releases/musl-@V@.tar.gz" xzf
	(
		cd "$WORK"/musl-*
		./configure --prefix="$WORK/musl" --target=$CROSS --disable-shared \
			CROSS_COMPILE=$CROSS- CFLAGS="$ARCH -Os" >/dev/null
		make -j"$(nproc)" install >/dev/null
	)
	CC="$WORK/musl/bin/musl-gcc"
	CFLAGS="$ARCH -Os"
	# libgcc of the glibc cross compiler calls raise(): link libc last,
	# otherwise every configure link test fails (and crypt() is not found)
	LIBS=-lc
fi

fetch "$SRC" "https://matt.ucc.asn.au/dropbear/releases/dropbear-@V@.tar.bz2" xjf
cd "$WORK"/dropbear-*

# OpenWrt's patch: allow root login with a blank password via the "none" auth
# method, so an image built with an empty ROOT_PASSWORD behaves like a fresh
# OpenWrt (passwordless first SSH). Harmless when root has a password set.
patch -p1 < "$TOP/files/dropbear-allow-blank-root-password.patch"

# Host keys stay in the default /etc/dropbear, which the init script
# bind-mounts from /data/dropbear
echo "#define DROPBEAR_X11FWD 0" > localoptions.h

./configure --host="$CROSS" --disable-zlib --enable-static \
	--disable-lastlog --disable-utmp --disable-utmpx --disable-wtmp \
	--disable-wtmpx --disable-pututline --disable-pututxline \
	CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="-static" LIBS="$LIBS" >/dev/null
grep -q "^#define HAVE_CRYPT 1" config.h || { echo "crypt() not found" >&2; exit 1; }
make -j"$(nproc)" PROGRAMS="dropbear dbclient dropbearkey scp" MULTI=1 STATIC=1 >/dev/null

"$CROSS-strip" -o "$OUT/dropbear" dropbearmulti
file "$OUT/dropbear"
