#!/bin/bash
set -euo pipefail # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

# 外へ出られるのは tinyproxy のユーザーだけで、tinyproxy が許可リスト (/etc/tinyproxy/allow.txt) のドメインへ
# CONNECT を中継する。IP で許可すると、同じ CDN の IP に載った別のサイトにも繋がり、CDN の IP が変わると切れる
PROXY=http://127.0.0.1:3128

# 1. Extract Docker DNS info BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush existing rules
# vscode は sudo でこのスクリプトを再実行できる。組み立て直す間に一度でも ACCEPT にすると、その隙に任意の宛先へ
# 繋いだ接続が ESTABLISHED の許可で残るため、方針は最初から DROP にしておき、必要な通信だけを先に許可する。
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# 2. Selectively restore ONLY internal Docker DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
  echo "Restoring Docker DNS rules..."
  iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
  iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
  echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
  echo "No Docker DNS rules to restore"
fi

# リゾルバは問い合わせを外へ中継するため、名前を引けるだけで持ち出しの経路になる。DNS は tinyproxy だけに許す。
# 127.0.0.11 (Docker の内蔵 DNS) は loopback の許可で通ってしまうので、その許可より前に塞ぐ
while read -r resolver; do
  echo "Allowing DNS to resolver $resolver for tinyproxy only"
  iptables -A OUTPUT -d "$resolver" -m owner ! --uid-owner tinyproxy -j REJECT
  iptables -A OUTPUT -d "$resolver" -p udp --dport 53 -j ACCEPT
  iptables -A OUTPUT -d "$resolver" -p tcp --dport 53 -j ACCEPT
done < <(awk '/^nameserver/ && $2 ~ /^[0-9.]+$/ {print $2}' /etc/resolv.conf)
# Allow localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

iptables -A OUTPUT -m owner --uid-owner tinyproxy -p tcp --dport 443 -j ACCEPT

# Get host IP from default route
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
  echo "ERROR: Failed to detect host IP"
  exit 1
fi

echo "Host gateway detected as: $HOST_IP"

# Allow only the gateway itself, not the whole host network
# (a /24 would expose the host LAN and sibling containers)
iptables -A INPUT -s "$HOST_IP" -j ACCEPT

# Explicitly REJECT all other outbound traffic for immediate feedback
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

pkill -x -U tinyproxy tinyproxy || true
while pgrep -x -U tinyproxy tinyproxy >/dev/null; do
  sleep 0.1
done
tinyproxy

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
if curl --noproxy '*' --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
  echo "ERROR: Firewall verification failed - was able to reach https://api.github.com directly"
  exit 1
else
  echo "Firewall verification passed - unable to reach https://api.github.com directly as expected"
fi

if curl -x "$PROXY" --connect-timeout 5 https://example.com >/dev/null 2>&1; then
  echo "ERROR: Firewall verification failed - was able to reach https://example.com through the proxy"
  exit 1
else
  echo "Firewall verification passed - unable to reach https://example.com through the proxy as expected"
fi

if ! curl -x "$PROXY" --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
  echo "ERROR: Firewall verification failed - unable to reach https://api.github.com through the proxy"
  exit 1
else
  echo "Firewall verification passed - able to reach https://api.github.com through the proxy as expected"
fi
