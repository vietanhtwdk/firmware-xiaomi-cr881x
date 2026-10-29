#!/bin/bash
# Build a static ARMv7 dropbear (multi-call: dropbear, dbclient, dropbearkey,
# scp) against musl. The stock dropbear 2017.75 only offers ssh-rsa, which
# OpenSSH >= 8.8 refuses by default; newer dropbear adds ed25519 and
# rsa-sha2-256. musl is needed: getpwnam()/crypt() do not work from a static
# glibc binary on the musl based firmware.
#
# Usage: tools/build-dropbear.sh [dropbear version] [out_dir]
# Needs: curl make gcc-arm-linux-gnueabihf

set -euo pipefail

DROPBEAR=${1:-2024.86}
OUT=${2:-out}
MUSL=1.2.5
CROSS=arm-linux-gnueabihf
ARCH="-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard"

command -v $CROSS-gcc >/dev/null || {
	echo "missing $CROSS-gcc (apt install gcc-arm-linux-gnueabihf)" >&2
	exit 1
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
cd "$WORK"

curl -sfL https://musl.libc.org/releases/musl-$MUSL.tar.gz | tar xz
curl -sfL https://matt.ucc.asn.au/dropbear/releases/dropbear-$DROPBEAR.tar.bz2 | tar xj

(
	cd musl-$MUSL
	./configure --prefix="$WORK/musl" --target=$CROSS --disable-shared \
		CROSS_COMPILE=$CROSS- CFLAGS="$ARCH -Os" >/dev/null
	make -j"$(nproc)" install >/dev/null
)

cd dropbear-$DROPBEAR
# Host keys stay in the default /etc/dropbear, which the init script
# bind-mounts from /data/dropbear
echo "#define DROPBEAR_X11FWD 0" > localoptions.h
# Link static with -lc last: libgcc of the Ubuntu cross compiler calls raise(),
# otherwise every configure link test fails (and crypt() is not detected)
./configure --host=$CROSS --disable-zlib --enable-static \
	--disable-lastlog --disable-utmp --disable-utmpx --disable-wtmp \
	--disable-wtmpx --disable-pututline --disable-pututxline \
	CC="$WORK/musl/bin/musl-gcc" CFLAGS="$ARCH -Os" \
	LDFLAGS=-static LIBS=-lc >/dev/null
grep -q "^#define HAVE_CRYPT 1" config.h || { echo "crypt() not found" >&2; exit 1; }
make -j"$(nproc)" PROGRAMS="dropbear dbclient dropbearkey scp" MULTI=1 STATIC=1 >/dev/null

$CROSS-strip -o "$OUT/dropbear" dropbearmulti
file "$OUT/dropbear"
