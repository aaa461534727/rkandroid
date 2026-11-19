#!/bin/bash
# lkb_test_ap.sh — 在本机 USB 网卡上自建一个已知密码的测试热点 (供 LKB3576 STA 关联/上网复验)
#
# 干什么: 起 hostapd(AP) + dnsmasq(DHCP) + iptables NAT(让板子经本机 ens33 上网),
#         这样验证 STA 不需要等外部热点密码。
# 怎么用: sudo bash scripts/lkb_test_ap.sh start|stop|status
# 依赖  : hostapd / dnsmasq / iw / iptables; 无线网卡需支持 AP 模式 (本机 wlx688fc9271e46)
# 在哪跑: 本机 dengbaowen-ubuntu (VM), 板子经以太网/无线连过来
# 产出  : /tmp/opencode/hostapd_lkb.log + /tmp/opencode/dnsmasq_lkb.log
#
# 参数 (可用环境变量覆盖): IFACE / SSID / PASS / CHAN / AP_IP / UPLINK

set -u
IFACE=${IFACE:-wlx688fc9271e46}
SSID=${SSID:-LKB_AP_TEST}
PASS=${PASS:-Lkb3576Test123}
CHAN=${CHAN:-6}
AP_IP=${AP_IP:-192.168.50.1}
UPLINK=${UPLINK:-ens33}
CONF=/tmp/opencode/hostapd_lkb.conf
HDIR=/tmp/opencode

[ "$(id -u)" = "0" ] || { echo "需要 root: sudo $0 $*"; exit 1; }

case "${1:-start}" in
start)
	# 1) 网卡交给 hostapd 管, 先断开 NetworkManager
	command -v nmcli >/dev/null && nmcli dev set "$IFACE" managed no 2>/dev/null
	ip link set "$IFACE" down 2>/dev/null
	ip addr flush dev "$IFACE" 2>/dev/null
	ip addr add "$AP_IP/24" dev "$IFACE"
	ip link set "$IFACE" up

	# 2) hostapd 配置
	# 注意 (2026-11-19 实测): 不写 ieee80211n=1 时 AP 是 802.11g 非 HT
	# (iw 显示 "20 MHz (no HT)"), 板子侧 setup TXBA 必然失败、持续压测丢包 74%。
	# 这里开 802.11n HT20 + SHORT-GI-20, 让 Block Ack 能建立。
	# HT=0 可退回 11g (用来对照: 板子 CP 的 TX A-MSDU 路径有 bug, 见 WORKLOG)
	if [ "${HT:-1}" = "1" ]; then
		HT_CONF="ieee80211n=1
ht_capab=[SHORT-GI-20]"
	else
		HT_CONF=""
	fi
	cat > "$CONF" <<-EOF
	interface=$IFACE
	driver=nl80211
	ssid=$SSID
	country_code=CN
	ieee80211d=1
	hw_mode=g
	channel=$CHAN
	$HT_CONF
	wmm_enabled=1
	auth_algs=1
	wpa=2
	wpa_passphrase=$PASS
	wpa_key_mgmt=WPA-PSK
	rsn_pairwise=CCMP
	EOF

	pkill -f "hostapd .*hostapd_lkb\.conf" 2>/dev/null; pkill -f "dnsmasq.*$IFACE" 2>/dev/null
	sleep 1
	hostapd -B -P "$HDIR/hostapd_lkb.pid" -f "$HDIR/hostapd_lkb.log" "$CONF" >/dev/null 2>&1
	sleep 3
	[ -s "$HDIR/hostapd_lkb.pid" ] && echo "hostapd pid=$(cat $HDIR/hostapd_lkb.pid)" || echo "hostapd 启动失败, 看 $HDIR/hostapd_lkb.log"

	# 3) DHCP + DNS
	dnsmasq --conf-file=/dev/null --interface="$IFACE" --bind-interfaces \
		--dhcp-range=192.168.50.10,192.168.50.60,12h \
		--dhcp-option=3,"$AP_IP" --dhcp-option=6,8.8.8.8,1.1.1.1 \
		--pid-file="$HDIR/dnsmasq_lkb.pid" --log-facility="$HDIR/dnsmasq_lkb.log" 2>/dev/null

	# 4) NAT: 板子 → 本机 → $UPLINK
	sysctl -qw net.ipv4.ip_forward=1
	iptables -t nat -C POSTROUTING -o "$UPLINK" -j MASQUERADE 2>/dev/null || \
		iptables -t nat -A POSTROUTING -o "$UPLINK" -j MASQUERADE
	iptables -C FORWARD -i "$IFACE" -o "$UPLINK" -j ACCEPT 2>/dev/null || {
		iptables -A FORWARD -i "$IFACE" -o "$UPLINK" -j ACCEPT
		iptables -A FORWARD -i "$UPLINK" -o "$IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
	}
	echo "AP 就绪: SSID=$SSID PASS=$PASS CHAN=$CHAN IP=$AP_IP (NAT -> $UPLINK)"
	;;
stop)
	pkill -f "hostapd .*hostapd_lkb\.conf" 2>/dev/null
	pkill -f "dnsmasq.*$IFACE" 2>/dev/null
	ip addr flush dev "$IFACE" 2>/dev/null
	iptables -t nat -D POSTROUTING -o "$UPLINK" -j MASQUERADE 2>/dev/null
	command -v nmcli >/dev/null && nmcli dev set "$IFACE" managed yes 2>/dev/null
	echo "AP 已停"
	;;
status)
	echo "--- hostapd ---"; tail -5 "$HDIR/hostapd_lkb.log" 2>/dev/null
	echo "--- 关联客户端 ---"; iw dev "$IFACE" station dump 2>/dev/null | grep -E "^Station|signal:" | head -10
	echo "--- dnsmasq 租约 ---"; grep -E "DHCPACK" "$HDIR/dnsmasq_lkb.log" 2>/dev/null | tail -5
	;;
*)
	echo "用法: sudo $0 start|stop|status"; exit 1 ;;
esac
