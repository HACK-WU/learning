#!/usr/bin/env bash
set -o pipefail

CP1=192.168.122.19
W1=192.168.122.54
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
K8S_VER=1.29

install_k8s() {
  local IP=$1
  echo "######## 安装 k8s 组件: $IP ########"
  ssh $SSHOPT k8s@$IP 'sudo -n bash -s' <<'EOS' 2>&1
set -e
set -o pipefail
export DEBIAN_FRONTEND=noninteractive
K8S_VER=1.29

echo "--- [1/4] 添加 k8s apt 源 ---"
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VER}/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>&1
echo "密钥写入: $(ls -l /etc/apt/keyrings/kubernetes-apt-keyring.gpg | awk '{print $5}') bytes"

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VER}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
cat /etc/apt/sources.list.d/kubernetes.list

echo ""
echo "--- [2/4] 安装 kubeadm/kubelet/kubectl ---"
apt-get update -qq 2>&1 | tail -2
apt-get install -y -qq kubelet kubeadm kubectl 2>&1 | tail -4
apt-mark hold kubelet kubeadm kubectl 2>&1 | tail -3

echo ""
echo "--- [3/4] 版本核验 ---"
kubeadm version -o short 2>&1
kubelet --version 2>&1
kubectl version --client 2>&1 | head -1

echo ""
echo "--- [4/4] 启用 kubelet ---"
systemctl enable --now kubelet 2>&1 | tail -1
echo "kubelet 状态: $(systemctl is-active kubelet 2>&1)  (初始化前为 activating/crash 属正常)"
EOS
  echo "退出码=$?"
  echo ""
}

install_k8s $CP1
install_k8s $W1
echo "========== k8s 组件安装完成 =========="
