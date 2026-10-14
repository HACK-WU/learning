#!/usr/bin/env bash
set -o pipefail

echo "=== [1/4] 虚机列表与 IP ==="
for i in $(seq 1 12); do
  virsh domifaddr k8s-cp1 2>&1 | grep -q ipv4 && break
  sleep 5
done

for NODE in k8s-cp1 k8s-w1; do
  echo "--- $NODE ---"
  virsh domifaddr $NODE 2>&1
done

echo ""
echo "=== [2/4] DHCP 租约（备用取 IP 方式）==="
virsh net-dhcp-leases default 2>&1

echo ""
echo "=== [3/4] libvirt 网络网段 ==="
virsh net-dumpxml default 2>&1 | grep -E 'ip address|netmask|dhcp|range' | head -8

echo ""
echo "=== [4/4] 虚机控制台可用性判定（取 cp1 的 IP 后 ping）==="
CP1_IP=$(virsh domifaddr k8s-cp1 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d/ -f1)
W1_IP=$(virsh domifaddr k8s-w1 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d/ -f1)
echo "CP1_IP=$CP1_IP"
echo "W1_IP=$W1_IP"

if [ -n "$CP1_IP" ]; then
  echo "--- ping $CP1_IP ---"
  ping -c 3 -W 3 "$CP1_IP" 2>&1 | tail -5
fi
