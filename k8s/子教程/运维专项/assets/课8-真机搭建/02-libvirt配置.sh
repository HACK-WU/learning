#!/usr/bin/env bash
set -o pipefail

echo "=== [1/5] 启动 libvirtd ==="
systemctl start libvirtd 2>&1 | tail -3
systemctl enable libvirtd 2>&1 | tail -2
sleep 3
echo "libvirtd 状态: $(systemctl is-active libvirtd 2>&1)"

echo ""
echo "=== [2/5] 默认网络 ==="
virsh net-list --all 2>&1
echo "--- 启动 default 网络 ---"
virsh net-start default 2>&1
virsh net-autostart default 2>&1
sleep 2
virsh net-list 2>&1

echo ""
echo "=== [3/5] 存储池 ==="
virsh pool-list --all 2>&1

echo ""
echo "=== [4/5] 下载 Ubuntu 22.04 云镜像 ==="
mkdir -p /var/lib/libvirt/images
IMG=/var/lib/libvirt/images/jammy-server-cloudimg-amd64.img
if [ -f "$IMG" ]; then
  echo "镜像已存在: $(ls -lh $IMG | awk '{print $5}')"
else
  echo "开始下载..."
  wget -q --show-progress -O "$IMG" https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img 2>&1 | tail -5
  echo "wget exit=$?"
  ls -lh "$IMG" 2>&1
fi

echo ""
echo "=== [5/5] 镜像信息 ==="
qemu-img info "$IMG" 2>&1 | head -12
