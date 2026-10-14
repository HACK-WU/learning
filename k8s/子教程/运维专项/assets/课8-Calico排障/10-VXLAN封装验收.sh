#!/usr/bin/env bash
set -o pipefail

CP1=192.168.122.19
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

echo "########## VXLAN 修复后：跨节点互通验证 ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
set -o pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "--- [1] 部署跨节点测试 Pod ---"
cat <<'YAML' | kubectl apply -f - 2>&1
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: netprobe
spec:
  selector:
    matchLabels:
      app: netprobe
  template:
    metadata:
      labels:
        app: netprobe
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: netprobe
        image: busybox:1.36
        command: ["sleep", "3600"]
YAML

kubectl wait --for=condition=Ready pod -l app=netprobe --timeout=180s 2>&1 | tail -2

echo ""
echo "--- [2] Pod 分布 ---"
kubectl get pods -l app=netprobe -o wide 2>&1
UNIQ=$(kubectl get pods -l app=netprobe -o jsonpath='{.items[*].spec.nodeName}' | tr ' ' '\n' | sort -u | wc -l)
echo "不同节点数=$UNIQ"

echo ""
echo "--- [3] 跨节点 ping ---"
P1=$(kubectl get pods -l app=netprobe -o jsonpath='{.items[0].metadata.name}')
P2=$(kubectl get pods -l app=netprobe -o jsonpath='{.items[1].metadata.name}')
IP2=$(kubectl get pods -l app=netprobe -o jsonpath='{.items[1].status.podIP}')
N1=$(kubectl get pods -l app=netprobe -o jsonpath='{.items[0].spec.nodeName}')
N2=$(kubectl get pods -l app=netprobe -o jsonpath='{.items[1].spec.nodeName}')
echo "$P1($N1) -> $P2($N2, $IP2)"
kubectl exec $P1 -- ping -c 4 -W 3 $IP2 2>&1 | tail -5

echo ""
echo "--- [4] DNS 解析验证（CoreDNS 是否工作）---"
kubectl exec $P1 -- nslookup kubernetes.default.svc.cluster.local 2>&1 | tail -8
EOS

echo ""
echo "########## 清理 ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl delete daemonset netprobe --ignore-not-found 2>&1
echo "已清理"
EOS
