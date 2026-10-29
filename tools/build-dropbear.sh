#!/bin/bash
# Build a static ARMv7 dropbear (multi-call: dropbear, dbclient, dropbearkey,
# scp). The stock dropbear 2017.75 only offers ssh-rsa, which OpenSSH >= 8.8
# refuses by default; newer dropbear adds ed25519 and rsa-sha2-256.
#
# Needs a real musl cross toolchain: getpwnam()/crypt() do not work from a
# static glibc binary, and musl-gcc on top of a glibc cross gcc produced a
# binary that crashed at startup. An OpenWrt ARMv7 toolchain works, e.g.
# from an ipq40xx build tree (make toolchain/install).
#
# Usage: tools/build-dropbear.sh <toolchain dir> <dropbear tarball|version> [out_dir]
#   toolchain dir: .../staging_dir/toolchain-arm_cortex-a7+neon-vfpv4_gcc-*_musl_eabi

set -euo pipefail

TC=${1:?toolchain dir}
SRC=${2:?dropbear tarball or version}
OUT=${3:-out}

CC=$(ls "$TC"/bin/*-linux-musl*-gcc 2>/dev/null | head -1)
[ -x "$CC" ] || { echo "no musl gcc in $TC/bin" >&2; exit 1; }
CROSS=$(basename "${CC%-gcc}")
export PATH="$TC/bin:$PATH" STAGING_DIR="$TC"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

if [ -f "$SRC" ]; then
	tar xjf "$SRC" -C "$WORK"
else
	curl -sfL "https://matt.ucc.asn.au/dropbear/releases/dropbear-$SRC.tar.bz2" | tar xj -C "$WORK"
fi
cd "$WORK"/dropbear-*

# Host keys stay in the default /etc/dropbear, which the init script
# bind-mounts from /data/dropbear
echo "#define DROPBEAR_X11FWD 0" > localoptions.h

./configure --host="$CROSS" --disable-zlib --enable-static \
	--disable-lastlog --disable-utmp --disable-utmpx --disable-wtmp \
	--disable-wtmpx --disable-pututline --disable-pututxline \
	CFLAGS="-Os" LDFLAGS="-static" >/dev/null
grep -q "^#define HAVE_CRYPT 1" config.h || { echo "crypt() not found" >&2; exit 1; }
make -j"$(nproc)" PROGRAMS="dropbear dbclient dropbearkey scp" MULTI=1 STATIC=1 >/dev/null

"$CROSS-strip" -o "$OUT/dropbear" dropbearmulti
file "$OUT/dropbear"
