#!/usr/bin/env bash
set -o pipefail

CP1=192.168.122.19
W1=192.168.122.54
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

echo "########## 修复：切换 Calico 为 VXLAN 封装 ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
set -e
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "--- [1] 当前 IPPool 配置 ---"
kubectl get ippool -o yaml 2>&1 | grep -E 'name:|cidr:|ipipMode|vxlanMode' | head -10

echo ""
echo "--- [2] 改为 VXLAN（Always）---"
cat <<'YAML' | kubectl apply -f - 2>&1
apiVersion: crd.projectcalico.org/v1
kind: IPPool
metadata:
  name: default-ipv4-ippool
spec:
  cidr: 10.244.0.0/16
  vxlanMode: Always
  ipipMode: Never
  natOutgoing: true
  blockSize: 26
YAML

echo ""
echo "--- [3] 重启 calico-node 使配置生效 ---"
kubectl rollout restart daemonset/calico-node -n kube-system 2>&1
kubectl rollout status daemonset/calico-node -n kube-system --timeout=180s 2>&1 | tail -3

echo ""
echo "--- [4] 等待 calico-node 就绪 ---"
for i in $(seq 1 30); do
  READY=$(kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers 2>/dev/null | awk '{print $2}' | grep -c '^1/1$')
  TOTAL=$(kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers 2>/dev/null | wc -l)
  echo "第 $i 次: $READY/$TOTAL 就绪"
  [ "$READY" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ] && break
  sleep 10
done
echo ""
kubectl get pods -n kube-system -l k8s-app=calico-node -o wide 2>&1
EOS
