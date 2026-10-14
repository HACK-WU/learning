#!/usr/bin/env bash
set -o pipefail

CP1=192.168.122.19
W1=192.168.122.54
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

echo "########## 边抓边 ping（同步）##########"
# 在 w1 后台启动抓包
ssh $SSHOPT k8s@$W1 'sudo -n bash -s' <<'EOS' > /tmp/tcpdump_w1.log 2>&1 &
setsid tcpdump -i any -c 20 -nn 'udp port 4789 or icmp' > /tmp/tcpdump_w1.log 2>&1
sleep 12
echo "抓包结束"
EOS

# 等抓包启动
sleep 2

# 部署并 ping
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
set -o pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
cat <<'YAML' | kubectl apply -f - >/dev/null 2>&1
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
kubectl wait --for=condition=Ready pod -l app=netprobe --timeout=120s >/dev/null 2>&1
WPOD=$(kubectl get pods -l app=netprobe -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{"\n"}{end}' | awk '$2=="k8s-w1"{print $1}')
CPOD=$(kubectl get pods -l app=netprobe -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{"\n"}{end}' | awk '$2=="k8s-cp1"{print $1}')
WIP=$(kubectl get pod $WPOD -o jsonpath='{.status.podIP}')
echo "从 $CPOD ping $WPOD ($WIP)"
kubectl exec $CPOD -- ping -c 3 -W 2 $WIP 2>&1 | tail -4

echo ""
echo "--- 关键：Pod 内 ARP 表（169.254.1.1 的 MAC）---"
kubectl exec $CPOD -- ip neigh show 2>&1
kubectl exec $CPOD -- arp -n 2>&1 | head -5

echo ""
echo "--- Pod 内 eth0 配置 ---"
kubectl exec $CPOD -- ip addr show eth0 2>&1 | head -5
EOS

echo ""
echo "########## 抓包结果 ##########"
ssh $SSHOPT k8s@$W1 'sudo -n cat /tmp/tcpdump_w1.log 2>&1' | head -25

echo ""
echo "########## 宿主机 cali 接口 ARP 代理 ##########"
for NODE_IP in $CP1 $W1; do
echo "======== $NODE_IP ========"
ssh $SSHOPT k8s@$NODE_IP 'sudo -n bash -s' <<'EOS' 2>&1
echo "--- proxy_arp 设置 ---"
sysctl -n net.ipv4.conf.all.proxy_arp 2>&1
echo "--- cali 接口 proxy_arp ---"
for i in $(ip link show | grep -o 'cali[a-f0-9]*' | head -2); do sysctl -n net.ipv4.conf.$i.proxy_arp 2>&1; done
echo "--- 邻居表（是否有 Pod IP 的条目）---"
ip neigh show | grep '10.244' | head -5
echo "--- 宿主机到对端 Pod IP 是否通 ---"
EOS
done

echo ""
echo "########## 清理 ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl delete daemonset netprobe --ignore-not-found >/dev/null 2>&1
echo "已清理"
EOS
