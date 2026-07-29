#!/bin/bash
# Tests per-connection WAN interface resolution (issue #10).

PASS=0
FAIL=0

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF -- "$needle"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf "FAIL: %s\n  expected to contain: '%s'\n  in: '%.400s'\n" "$desc" "$needle" "$haystack"
    fi
}

MOCKDIR=$(mktemp -d)
MOCKBIN="$MOCKDIR/bin"
mkdir -p "$MOCKBIN"

cat > "$MOCKBIN/uci" <<'MOCK'
#!/bin/sh
case "$*" in
    *"firewall.@zone[0].name"*) echo wan ;;
    *"firewall.@zone[0].masq"*) echo 1 ;;
    *"firewall.@zone[0].network"*) echo "wan wanb" ;;
    *"firewall.@zone[1].name"*) echo "" ;;
    *network.lan.device*) echo br-lan ;;
    *) echo "" ;;
esac
MOCK
chmod +x "$MOCKBIN/uci"

cat > "$MOCKBIN/ubus" <<'MOCK'
#!/bin/sh
case "$2" in
    network.interface.wan)
        echo '{"l3_device":"pppoe-wan","device":"pppoe-wan"}'
        ;;
    network.interface.wanb)
        echo '{"l3_device":"eth1","device":"eth1"}'
        ;;
    *) echo "" ;;
esac
MOCK
chmod +x "$MOCKBIN/ubus"

cat > "$MOCKBIN/jsonfilter" <<'MOCK'
#!/bin/sh
input=$(cat)
expr=""
while [ $# -gt 0 ]; do
    case "$1" in
        -e) expr="$2"; shift ;;
    esac
    shift
done
case "$expr" in
    '@.l3_device') echo "$input" | sed -n 's/.*"l3_device":"\([^"]*\)".*/\1/p' ;;
    '@.device') echo "$input" | sed -n 's/.*"device":"\([^"]*\)".*/\1/p' ;;
    *) echo "" ;;
esac
MOCK
chmod +x "$MOCKBIN/jsonfilter"

PATH="$MOCKBIN:$PATH"
export PATH

. "$(dirname "$0")/../luci-app-trafficctl/root/usr/local/bin/trafficctl-fw.sh"

TCTL_NETDEV_MAP=""
TCTL_MARK_MAP="0x100:wan,0x200:wanb,256:wan,512:wanb"
_dev=""
_name=""
while read -r _dev _name; do
    [ -z "$_dev" ] || [ -z "$_name" ] && continue
    if [ -n "$TCTL_NETDEV_MAP" ]; then TCTL_NETDEV_MAP="$TCTL_NETDEV_MAP,"; fi
    TCTL_NETDEV_MAP="${TCTL_NETDEV_MAP}${_dev}:${_name}"
done <<EOF
$(tctl_wan_netdev_map)
EOF

assert_contains "netdev map includes pppoe-wan" "pppoe-wan:wan" "$TCTL_NETDEV_MAP"
assert_contains "netdev map includes eth1" "eth1:wanb" "$TCTL_NETDEV_MAP"

IP="192.168.0.50"
CONNTRACK_DATA='ipv4 2 tcp 6 120 src=192.168.0.50 dst=8.8.8.8 sport=40000 dport=443 src=8.8.8.8 dst=192.168.0.50 sport=443 dport=40000 [ASSURED] mark=0x100 bytes=1000 packets=10 bytes=500 packets=5 oifname=pppoe-wan iifname=br-lan
ipv4 2 tcp 6 60 src=192.168.0.50 dst=1.1.1.1 sport=40001 dport=443 src=1.1.1.1 dst=192.168.0.50 sport=443 dport=40001 [ASSURED] mark=0x200 bytes=2000 packets=20 bytes=800 packets=8 oifname=eth1 iifname=br-lan'

CONNS_OUT=$(echo "$CONNTRACK_DATA" | awk -v ip="$IP" -v pf="all" \
    -v netdev_map="$TCTL_NETDEV_MAP" -v mark_map="$TCTL_MARK_MAP" '
function resolve_wan(oif, mark,    parts, i, n, kv, mkey) {
    mkey = mark
    if (mkey != "" && mkey != "0" && mkey != "0x0") {
        n = split(mark_map, parts, ",")
        for (i = 1; i <= n; i++) {
            split(parts[i], kv, ":")
            if (kv[1] == mkey) return kv[2]
        }
    }
    if (oif != "") {
        n = split(netdev_map, parts, ",")
        for (i = 1; i <= n; i++) {
            split(parts[i], kv, ":")
            if (kv[1] == oif) return kv[2]
        }
        return oif
    }
    return ""
}
BEGIN { n=0 }
{
    proto=""
    for (i=1; i<=NF; i++) {
        if ($i == "tcp") proto="tcp"
        else if ($i == "udp") proto="udp"
    }
    dst=""; dport=""; bytes=0; state=""; oif=""; mark=""
    src_key = "src=" ip
    seen_src=0; got_dst=0
    for (i=1; i<=NF; i++) {
        if ($i == src_key && !seen_src) { seen_src=1; continue }
        if (seen_src && !got_dst && index($i, "dst=") == 1) { dst=substr($i, 5); got_dst=1 }
        if (seen_src && !got_dst) continue
        if (seen_src && index($i, "dport=") == 1 && dport == "") dport=substr($i, 7)
        if (seen_src && index($i, "bytes=") == 1 && bytes == 0) bytes=substr($i, 7)+0
        if (index($i, "oifname=") == 1 && oif == "") oif=substr($i, 9)
        if (index($i, "mark=") == 1 && mark == "") {
            mark=substr($i, 6)
            if (index(mark, "0x") == 1 || index(mark, "0X") == 1) mark=tolower(mark)
        }
    }
    if (dst == "" || dst == ip) next
    if (dport == "") dport = "0"
    if (n > 0) printf ","
    wan = resolve_wan(oif, mark)
    printf "{\"proto\":\"%s\",\"dst\":\"%s\",\"wan\":\"%s\"}", proto, dst, wan
    n++
}
')

assert_contains "conn 8.8.8.8 resolved to wan" '"dst":"8.8.8.8","wan":"wan"' "$CONNS_OUT"
assert_contains "conn 1.1.1.1 resolved to wanb" '"dst":"1.1.1.1","wan":"wanb"' "$CONNS_OUT"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
rm -rf "$MOCKDIR"
[ "$FAIL" -eq 0 ] || exit 1
