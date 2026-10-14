#!/usr/bin/env bash
set -o pipefail

CP1=192.168.122.19
W1=192.168.122.54
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

echo "########## BGP 对等状态诊断 ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "--- [1] calico-node 就绪探针详情 ---"
for POD in $(kubectl get pods -n kube-system -l k8s-app=calico-node -o jsonpath='{.items[*].metadata.name}'); do
  NODE=$(kubectl get pod -n kube-system $POD -o jsonpath='{.spec.nodeName}')
  echo "== $POD ($NODE) =="
  kubectl get pod -n kube-system $POD -o jsonpath='{.status.containerStatuses[0].ready}{" ready\n"}{.status.containerStatuses[0].state}{"\n"}' 2>&1
  echo "--- readiness probe 失败原因 ---"
  kubectl describe pod -n kube-system $POD 2>&1 | grep -i -B2 -A6 'readiness' | head -20
  echo ""
done

echo "--- [2] 检查 calico-node 的 BGP 状态（用 calicoctl 风格）---"
CPOD=$(kubectl get pods -n kube-system -l k8s-app=calico-node -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{"\n"}{end}' | awk '$2=="k8s-cp1"{print $1}')
echo "cp1 pod=$CPOD"
kubectl exec -n kube-system $CPOD -- /bin/calico-node -felix 2>&1 | head -3
echo "--- bird BGP 邻居 ---"
kubectl exec -n kube-system $CPOD -- birdcl -v 2>&1 | head -2 || echo "birdcl 不可用"
EOS

echo ""
echo "########## 节点侧：bird 与 IPIP ##########"
for NODE_IP in $CP1 $W1; do
echo "======== $NODE_IP ========"
ssh $SSHOPT k8s@$NODE_IP 'sudo -n bash -s' <<'EOS' 2>&1
echo "--- calico-node 进程 ---"
ps aux | grep -c '[c]alico-node'
echo "--- bird 进程 ---"
ps aux | grep '[b]ird' | head -3
echo "--- confd 状态 ---"
ps aux | grep '[c]onfd' | head -2
echo "--- 节点 IPIP 隧道 ---"
ip tunnel show 2>&1 | head -5
echo "--- 到对端 Pod 网段的路由（关键）---"
ip route | grep '10.244' 
EOS
done

echo ""
echo "########## 直接测试 IPIP 连通性 ##########"
ssh $SSHOPT k8s@$W1 'sudo -n bash -s' <<'EOS' 2>&1
echo "--- w1 ping cp1 的 tunl0 (10.244.71.64) ---"
ping -c 3 -W 3 10.244.71.64 2>&1 | tail -4
echo "--- w1 ping cp1 主机 (192.168.122.19) ---"
ping -c 2 -W 3 192.168.122.19 2>&1 | tail -4
echo "--- IPIP 协议是否可达（协议号 4）---"
cat /proc/net/protocols 2>/dev/null | grep -i ipip || echo "ipip 未在协议表"
lsmod | grep -i ipip || echo "ipip 模块未加载"
EOS
