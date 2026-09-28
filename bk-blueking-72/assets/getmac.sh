#!/usr/bin/env bash
echo "=== WSL 所有网卡 MAC ==="
for f in /sys/class/net/*; do
  echo "$(basename $f): $(cat $f/address 2>/dev/null)"
done

echo ""
echo "=== 出口网卡（对外通信用的那张） ==="
ip route get 1.1.1.1 2>/dev/null | head -2

echo ""
echo "=== 主机名 ==="
hostname
