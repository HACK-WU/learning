#!/usr/bin/env bash
set -o pipefail

CP1=192.168.122.19
W1=192.168.122.54
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

configure_node() {
  local IP=$1
  echo "######## 配置 $IP ########"
  ssh $SSHOPT k8s@$IP 'sudo -n bash -s' <<'EOS' 2>&1
set -e
set -o pipefail
export DEBIAN_FRONTEND=noninteractive
HOST=$(hostname)

echo "--- 真实内存(MB) ---"
free -m | awk '/Mem:/ {print "total="$2"MB available="$7"MB"}'

echo ""
echo "--- [1/6] 关闭 swap ---"
swapoff -a 2>&1 || true
# 精确注释 swap 行
if [ -f /etc/fstab ]; then
  sed -i.bak 's|^\([^#].*\sswap\s\)|#\1|' /etc/fstab 2>&1 || true
fi
echo "当前 swap: $(swapon --show | wc -l) 个（0=已关闭）"

echo ""
echo "--- [2/6] 加载内核模块 ---"
cat > /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay 2>&1 || true
modprobe br_netfilter 2>&1 || true
echo "已加载：$(lsmod | grep -cE '^(overlay|br_netfilter)') 个（应为 2）"
lsmod | grep -E '^(overlay|br_netfilter)' | awk '{print "  " $1}'

echo ""
echo "--- [3/6] 设置 sysctl ---"
cat > /etc/sysctl.d/k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null 2>&1 || true
echo "核验值："
sysctl -n net.bridge.bridge-nf-call-iptables 2>&1 | xargs -I{} echo "  bridge-nf-call-iptables = {}"
sysctl -n net.ipv4.ip_forward 2>&1 | xargs -I{} echo "  ip_forward = {}"

echo ""
echo "--- [4/6] 安装 containerd（apt 源自动）---"
apt-get update -qq 2>&1 | tail -2
apt-get install -y -qq apt-transport-https ca-certificates curl gpg containerd 2>&1 | tail -3
echo "containerd 安装完成"

echo ""
echo "--- [5/6] 配置 containerd SystemdCgroup ---"
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml 2>&1
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
echo "SystemdCgroup 设置：$(grep -m1 'SystemdCgroup' /etc/containerd/config.toml)"
systemctl restart containerd 2>&1 || true
systemctl enable containerd >/dev/null 2>&1 || true
sleep 3
echo "containerd 状态: $(systemctl is-active containerd 2>&1)"

echo ""
echo "--- [6/6] 节点 $HOST 配置完成 ---"
EOS
  echo "退出码=$?"
  echo ""
}

configure_node $CP1
configure_node $W1

echo "========== 两节点前置配置完成 =========="
