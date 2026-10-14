#!/usr/bin/env bash
set -o pipefail

CP1=192.168.122.19
W1=192.168.122.54
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

echo "########## 诊断：跨节点 Pod 不通根因 ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "--- [1] calico-node 在 w1 上的状态 ---"
kubectl get pods -n kube-system -l k8s-app=calico-node -o wide 2>&1
echo ""
echo "--- [2] calico-node(w1) 就绪探针为何失败 ---"
CPOD=$(kubectl get pods -n kube-system -l k8s-app=calico-node -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{"\n"}{end}' | awk '$2=="k8s-w1"{print $1}')
echo "w1 上的 calico pod: $CPOD"
kubectl describe pod -n kube-system $CPOD 2>&1 | grep -A15 -i 'conditions\|events' | tail -25
echo ""
echo "--- [3] calico-node(w1) 日志尾 ---"
kubectl logs -n kube-system $CPOD --tail=30 2>&1
EOS

echo ""
echo "########## 节点侧排查 ##########"
for NODE_IP in $CP1 $W1; do
echo "======== $NODE_IP ========"
ssh $SSHOPT k8s@$NODE_IP 'sudo -n bash -s' <<'EOS' 2>&1
echo "--- 路由表（跨节点 Pod 网段应有路由）---"
ip route | grep -E '10.244|192.168.122' | head -8
echo ""
echo "--- 网卡 ---"
ip -brief addr show | head -8
echo ""
echo "--- BGP 端口 179 ---"
ss -tlnp 2>/dev/null | grep 179 || echo "179 端口未监听"
echo ""
echo "--- 防火墙 ---"
iptables -L -n 2>/dev/null | grep -i -E 'calico|DROP|REJECT' | head -8
echo ""
echo "--- 内核转发 ---"
sysctl -n net.ipv4.ip_forward
EOS
done
