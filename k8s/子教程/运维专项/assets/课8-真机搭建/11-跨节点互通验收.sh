#!/usr/bin/env bash
set -o pipefail

CP1=192.168.122.19
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

echo "########## 真·跨节点 Pod 互通验证 ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
set -o pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "--- [0] 清理旧测试 ---"
kubectl delete deployment nginx-test --ignore-not-found 2>&1

echo ""
echo "--- [1] 关键事实：控制面默认有 NoSchedule 污点 ---"
kubectl describe node k8s-cp1 2>&1 | grep -A2 -i 'taints' | head -5

echo ""
echo "--- [2] 用 DaemonSet 保证两节点各一个 Pod（可绕过污点）---"
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

echo ""
echo "--- [3] 等待两节点 Pod 就绪 ---"
kubectl wait --for=condition=Ready pod -l app=netprobe --timeout=180s 2>&1 | tail -3

echo ""
echo "--- [4] 确认 Pod 分布（必须跨节点）---"
kubectl get pods -l app=netprobe -o wide 2>&1
NODES=$(kubectl get pods -l app=netprobe -o jsonpath='{.items[*].spec.nodeName}')
echo "所在节点: $NODES"
UNIQ=$(echo $NODES | tr ' ' '\n' | sort -u | wc -l)
echo "不同节点数: $UNIQ（>=2 才是真跨节点）"

echo ""
echo "--- [5] 跨节点 Pod 互通测试 ---"
POD1=$(kubectl get pods -l app=netprobe -o jsonpath='{.items[0].metadata.name}')
POD2=$(kubectl get pods -l app=netprobe -o jsonpath='{.items[1].metadata.name}')
IP2=$(kubectl get pods -l app=netprobe -o jsonpath='{.items[1].status.podIP}')
NODE1=$(kubectl get pods -l app=netprobe -o jsonpath='{.items[0].spec.nodeName}')
NODE2=$(kubectl get pods -l app=netprobe -o jsonpath='{.items[1].spec.nodeName}')
echo "从 $POD1 (节点=$NODE1) ping $POD2 (节点=$NODE2, IP=$IP2)"
kubectl exec $POD1 -- ping -c 4 -W 3 $IP2 2>&1 | tail -6

echo ""
echo "--- [6] 跨节点 Service 互通 ---"
kubectl create service clusterip netprobe-svc --tcp=80:80 2>&1
echo "(Service 需匹配 Pod，改用直接验证 DNS)"
kubectl exec $POD1 -- nslookup kubernetes.default.svc.cluster.local 2>&1 | tail -6
EOS

echo ""
echo "########## 清理 ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl delete daemonset netprobe --ignore-not-found 2>&1
echo "已清理测试负载"
EOS
