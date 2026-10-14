#!/usr/bin/env bash
set -o pipefail

CP1=192.168.122.19
W1=192.168.122.54
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

echo "########## 检查 VXLAN 切换后状态 ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "--- calico Pod ---"
kubectl get pods -n kube-system -l k8s-app=calico-node -o wide 2>&1
echo ""
echo "--- 未就绪原因 ---"
for POD in $(kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null); do
  echo "== $POD =="
  kubectl describe pod -n kube-system $POD 2>&1 | grep -i -A4 'readiness probe failed\|unhealthy' | tail -6
done
EOS

echo ""
echo "########## 节点路由（关键：w1 是否学到 cp1 网段）##########"
for NODE_IP in $CP1 $W1; do
echo "======== $NODE_IP ========"
ssh $SSHOPT k8s@$NODE_IP 'sudo -n bash -s' <<'EOS' 2>&1
ip route | grep '10.244' | head -6
echo "--- vxlan 设备 ---"
ip -d link show type vxlan 2>&1 | head -4
EOS
done
