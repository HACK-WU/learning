#!/usr/bin/env bash
set -o pipefail
export DEBIAN_FRONTEND=noninteractive

echo "=== [1/4] apt update ==="
apt-get update -qq 2>&1 | tail -5
echo "apt update exit=$?"

echo ""
echo "=== [2/4] 安装 KVM 工具链 ==="
apt-get install -y -qq cpu-checker qemu-kvm libvirt-daemon-system libvirt-clients virtinst bridge-utils cloud-image-utils 2>&1 | tail -15
echo "install exit=$?"

echo ""
echo "=== [3/4] 版本确认 ==="
for c in qemu-system-x86_64 virsh virt-install cloud-localds; do
  printf "%-22s " "$c"
  $c --version 2>&1 | head -1
done

echo ""
echo "=== [4/4] 嵌套虚拟化可用性判定 ==="
echo "--- /dev/kvm ---"
ls -l /dev/kvm 2>&1
echo "--- kvm-ok ---"
kvm-ok 2>&1
echo "--- 当前用户组 ---"
id
