#!/bin/bash
# Build a static ARMv7 zerotier-one for the Xiaomi firmware (OpenWrt 18.06,
# old musl): a static binary does not depend on the libraries in the image.
#
# Usage: tools/build-zerotier.sh [version] [out_dir]
# Needs: git make g++-arm-linux-gnueabihf

set -euo pipefail

VERSION=${1:-1.14.2}
OUT=${2:-out}
CROSS=arm-linux-gnueabihf

command -v $CROSS-g++ >/dev/null || {
	echo "missing $CROSS-g++ (apt install g++-arm-linux-gnueabihf)" >&2
	exit 1
}

SRC=$(mktemp -d)
trap 'rm -rf "$SRC"' EXIT
git clone -q --depth 1 --branch "$VERSION" https://github.com/zerotier/ZeroTierOne "$SRC"

# SSO needs Rust, not useful on a router
make -C "$SRC" -j"$(nproc)" one \
	CC=$CROSS-gcc CXX=$CROSS-g++ STRIP=$CROSS-strip \
	ZT_STATIC=1 ZT_SSO_SUPPORTED=0 \
	CFLAGS="-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard" \
	CXXFLAGS="-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard"

mkdir -p "$OUT"
$CROSS-strip -o "$OUT/zerotier-one" "$SRC/zerotier-one"
file "$OUT/zerotier-one"
