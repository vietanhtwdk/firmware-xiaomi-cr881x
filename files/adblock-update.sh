#!/bin/sh
# On-router adblock list updater for dnsmasq.
#   sh /data/adblock-update.sh            # refresh and reload dnsmasq
# Lists (hosts format) are read from /data/adblock.lists, one URL per line;
# a default is written on first run. Output: /data/dnsmasq.d/adblock.conf
#
# One-time setup (persists in /data via uci config):
#   uci set dhcp.@dnsmasq[0].confdir=/data/dnsmasq.d
#   uci commit dhcp
#   sh /data/adblock-update.sh

set -e

DIR=/data/dnsmasq.d
LISTS=/data/adblock.lists
OUT="$DIR/adblock.conf"
TMP=/tmp/adblock.$$

mkdir -p "$DIR"
[ -s "$LISTS" ] || cat > "$LISTS" <<'EOF'
https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
EOF

: > "$TMP"
while read -r url; do
	case "$url" in ""|\#*) continue ;; esac
	echo "fetch $url"
	curl -fsSL "$url" >> "$TMP" || { echo "failed: $url" >&2; }
done < "$LISTS"

awk '
	/^[ 	]*#/ { next }
	{ sub(/#.*/, "") }
	$1 == "0.0.0.0" || $1 == "127.0.0.1" {
		d = tolower($2)
		if (d == "" || d == "localhost" || d == "localhost.localdomain") next
		if (d ~ /^[a-z0-9_]([a-z0-9_-]*\.)+[a-z][a-z]+$/) print d
	}
' "$TMP" | sort -u | awk '{ print "address=/" $0 "/#" }' > "$OUT.new"
rm -f "$TMP"

n=$(wc -l < "$OUT.new")
if [ "$n" -lt 100 ]; then
	echo "only $n domains, keeping previous list" >&2
	rm -f "$OUT.new"
	exit 1
fi
mv "$OUT.new" "$OUT"
echo "adblock: $n domains -> $OUT"

/etc/init.d/dnsmasq restart
echo "dnsmasq reloaded"
