#!/bin/bash
# Generate a dnsmasq sinkhole config from one or more hosts-format blocklists.
# Output uses address=/domain/# so every subdomain is blocked too (NXDOMAIN-
# style NODATA answer). Load it on the router from /data/dnsmasq.d (see README).
#
# Usage: tools/adblock-gen.sh [out_file] [list_url ...]
# Needs: curl, awk, sort

set -euo pipefail

OUT=${1:-out/adblock.conf}
shift || true
LISTS=("$@")
if [ ${#LISTS[@]} -eq 0 ]; then
	LISTS=(
		https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
	)
fi

mkdir -p "$(dirname "$OUT")"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

for url in "${LISTS[@]}"; do
	echo "fetch $url" >&2
	curl -fsSL "$url" >> "$TMP"
done

# hosts lines: "0.0.0.0 domain" / "127.0.0.1 domain"; keep the domain only,
# drop comments, localhost and anything that is not a plausible host name
awk '
	/^[ 	]*#/ { next }
	{ sub(/#.*/, "") }
	$1 == "0.0.0.0" || $1 == "127.0.0.1" {
		d = tolower($2)
		if (d == "" || d == "localhost" || d == "localhost.localdomain") next
		if (d ~ /^[a-z0-9_]([a-z0-9_-]*\.)+[a-z]{2,}$/) print d
	}
' "$TMP" | sort -u | awk '{ print "address=/" $0 "/#" }' > "$OUT"

n=$(wc -l < "$OUT")
sz=$(du -h "$OUT" | cut -f1)
echo "wrote $OUT: $n domains, $sz" >&2
