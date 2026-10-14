#!/usr/bin/env bash
set -o pipefail

IMG=/var/lib/libvirt/images/jammy-server-cloudimg-amd64.img
DISKDIR=/var/lib/libvirt/images

# 内存核算：WSL 可用约 8G，先起 1 台 2G 验证，成功后再扩
echo "=== 创建前内存 ==="
free -g | head -2

for NODE in k8s-cp1 k8s-w1; do
  echo ""
  echo "########## 创建 $NODE ##########"
  DISK=$DISKDIR/$NODE.qcow2

  # 1) 建磁盘（20G，基于云镜像的增量盘）
  if [ -f "$DISK" ]; then
    echo "磁盘已存在，跳过"
  else
    qemu-img create -f qcow2 -F qcow2 -b "$IMG" "$DISK" 20G 2>&1
    echo "create exit=$?"
  fi
  qemu-img info "$DISK" 2>&1 | grep -E 'virtual size|backing file'

  # 2) 生成 cloud-init 配置
  cat > /tmp/$NODE-user-data <<EOF
#cloud-config
hostname: $NODE
fqdn: $NODE
manage_etc_hosts: true
users:
  - name: k8s
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: 'k8s1234'
ssh_pwauth: true
disable_root: false
package_update: false
EOF

  cat > /tmp/$NODE-meta-data <<EOF
instance-id: $NODE
local-hostname: $NODE
EOF

  cloud-localds "$DISKDIR/$NODE-seed.qcow2" /tmp/$NODE-user-data /tmp/$NODE-meta-data 2>&1
  echo "cloud-localds exit=$?"

  # 3) 定义并启动虚机（2C/2G）
  if virsh dominfo $NODE >/dev/null 2>&1; then
    echo "虚机已定义，跳过创建"
  else
    virt-install \
      --name $NODE \
      --memory 2048 \
      --vcpus 2 \
      --disk path=$DISK,format=qcow2 \
      --disk path=$DISKDIR/$NODE-seed.qcow2,format=qcow2 \
      --os-variant ubuntu22.04 \
      --network network=default \
      --graphics none \
      --console pty,target_type=serial \
      --import \
      --noautoconsole 2>&1 | tail -8
    echo "virt-install exit=$?"
  fi
done

echo ""
echo "=== 拉取后状态 ==="
sleep 8
virsh list --all 2>&1
echo ""
free -g | head -2
