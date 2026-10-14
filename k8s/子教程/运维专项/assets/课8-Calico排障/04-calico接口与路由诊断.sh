#!/usr/bin/env bash
set -o pipefail

CP1=192.168.122.19
W1=192.168.122.54
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

for NODE_IP in $CP1 $W1; do
echo "############ $NODE_IP ############"
ssh $SSHOPT k8s@$NODE_IP 'sudo -n bash -s' <<'EOS' 2>&1
echo "--- [1] 所有接口 ---"
ip -brief link show 2>&1
echo ""
echo "--- [2] cali 接口数 ---"
ip link show | grep -c 'cali' || echo 0
echo ""
echo "--- [3] 完整路由表 ---"
ip route 2>&1
echo ""
echo "--- [4] Pod 网段黑洞路由（关键）---"
ip route | grep -E 'blackhole|10.244' 
echo ""
echo "--- [5] iptables nat 表（是否有 cali 链）---"
iptables -t nat -L -n 2>/dev/null | grep -c 'cali' || echo "0"
echo ""
echo "--- [6] calico felix 日志中的错误 ---"
journalctl -u containerd --no-pager -n 5 2>&1 | tail -3
EOS
echo ""
done

echo "############ 对比：cp1 有 cali，w1 没有 ############"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "--- w1 上 calico-node 的 felix 日志（查 cali 创建失败）---"
WPOD=$(kubectl get pods -n kube-system -l k8s-app=calico-node -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{"\n"}{end}' | awk '$2=="k8s-w1"{print $1}')
echo "w1 calico pod=$WPOD"
kubectl logs -n kube-system $WPOD --tail=40 2>&1 | grep -i -E 'error|fail|warn|cali|dataplane' | tail -20
EOS
