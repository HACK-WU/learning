#!/usr/bin/env bash
set -o pipefail

CP1=192.168.122.19
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

echo "########## [1/4] 等待全部节点 Ready ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
export KUBECONFIG=/etc/kubernetes/admin.conf
for i in $(seq 1 30); do
  NOTREADY=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2!="Ready"' | wc -l)
  echo "第 $i 次: 未Ready节点数=$NOTREADY"
  if [ "$NOTREADY" -eq 0 ]; then
    echo "全部节点 Ready"
    break
  fi
  sleep 10
done
echo ""
echo "=== 节点终态 ==="
kubectl get nodes -o wide 2>&1
EOS

echo ""
echo "########## [2/4] 等待全部 Pod Running ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
export KUBECONFIG=/etc/kubernetes/admin.conf
for i in $(seq 1 30); do
  NOPOD=$(kubectl get pods -A --no-headers 2>/dev/null | awk '$4!="Running" && $4!="Completed"' | wc -l)
  echo "第 $i 次: 未Running Pod数=$NOPOD"
  if [ "$NOPOD" -eq 0 ]; then
    echo "全部 Pod Running"
    break
  fi
  sleep 10
done
echo ""
echo "=== Pod 终态 ==="
kubectl get pods -A -o wide 2>&1
EOS

echo ""
echo "########## [3/4] 部署测试负载验证跨节点网络 ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
set -o pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl create deployment nginx-test --image=nginx:alpine --replicas=2 2>&1
kubectl scale deployment nginx-test --replicas=2 >/dev/null 2>&1
echo "--- 等待 Pod 调度 ---"
kubectl wait --for=condition=Ready pod -l app=nginx-test --timeout=180s 2>&1 | tail -3
echo ""
echo "--- Pod 分布（验证是否跨节点调度）---"
kubectl get pods -l app=nginx-test -o wide 2>&1
echo ""
echo "--- 验证跨节点 Pod 互通（在 cp1 的 pod 里 ping w1 的 pod）---"
PODS=($(kubectl get pods -l app=nginx-test -o jsonpath='{.items[*].metadata.name}'))
IPS=($(kubectl get pods -l app=nginx-test -o jsonpath='{.items[*].status.podIP}'))
NODES=($(kubectl get pods -l app=nginx-test -o jsonpath='{.items[*].spec.nodeName}'))
echo "Pod列表: ${PODS[@]}"
echo "Pod IP: ${IPS[@]}"
echo "所在节点: ${NODES[@]}"
if [ ${#IPS[@]} -ge 2 ]; then
  kubectl exec ${PODS[0]} -- ping -c 3 -W 3 ${IPS[1]} 2>&1 | tail -5
fi
EOS

echo ""
echo "########## [4/4] 集群最终验收 ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "=== 组件健康 ==="
kubectl get cs 2>&1
echo ""
echo "=== 节点 ==="
kubectl get nodes 2>&1
echo ""
echo "=== 版本 ==="
kubectl version --short 2>&1
echo ""
echo "=== 服务端点 ==="
kubectl get endpoints kubernetes -o wide 2>&1
EOS
