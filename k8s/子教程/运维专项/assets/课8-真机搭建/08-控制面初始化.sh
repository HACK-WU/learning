#!/usr/bin/env bash
set -o pipefail

CP1=192.168.122.19
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
POD_CIDR=10.244.0.0/16

echo "########## [阶段1] kubeadm init 预检 ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
set -o pipefail
echo "--- 内存核验（kubeadm 要求控制面 >= 2GB）---"
free -m | awk '/Mem:/ {print "total="$2"MB, available="$7"MB"}'
echo "--- CPU ---"
echo "nproc=$(nproc)"
echo "--- 预拉镜像（避免 init 超时）---"
kubeadm config images pull --kubernetes-version v1.29.15 2>&1 | tail -12
echo "pull exit=$?"
EOS

echo ""
echo "########## [阶段2] 执行 kubeadm init ##########"
ssh $SSHOPT k8s@$CP1 "sudo -n bash -s" <<EOS 2>&1
set -o pipefail
kubeadm init \\
  --kubernetes-version v1.29.15 \\
  --pod-network-cidr=$POD_CIDR \\
  --apiserver-advertise-address=$CP1 \\
  --ignore-preflight-errors=NumCPU,Mem \\
  --v=1 2>&1 | tail -45
echo "INIT_EXIT=\${PIPESTATUS[0]}"
EOS

echo ""
echo "########## [阶段3] init 结果判定 ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
echo "--- admin.conf 是否生成 ---"
ls -l /etc/kubernetes/admin.conf 2>&1
echo "--- kubelet 状态 ---"
systemctl is-active kubelet 2>&1
echo "--- 控制面组件容器 ---"
crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps 2>&1 | head -10
EOS
