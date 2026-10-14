#!/usr/bin/env bash
set -o pipefail

CP1=192.168.122.19
W1=192.168.122.54
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

echo "########## 抓包定位：报文死在哪 ##########"
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
echo "Pod 就绪"
kubectl get pods -l app=netprobe -o wide 2>&1

# 在 w1 的 Pod 侧抓包，看是否收到 cp1 来的包
WPOD=$(kubectl get pods -l app=netprobe -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{"\n"}{end}' | awk '$2=="k8s-w1"{print $1}')
CPOD=$(kubectl get pods -l app=netprobe -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{"\n"}{end}' | awk '$2=="k8s-cp1"{print $1}')
WIP=$(kubectl get pod $WPOD -o jsonpath='{.status.podIP}')
echo "cp1_pod=$CPOD  w1_pod=$WPOD  w1_pod_ip=$WIP"

echo ""
echo "--- 测量方法核验1: busybox ping 是否本身可用（ping 自己的网关/宿主机）---"
kubectl exec $WPOD -- ping -c 2 -W 2 192.168.122.54 2>&1 | tail -4

echo ""
echo "--- 测量方法核验2: 用 wget 测 TCP 而非 ICMP ---"
kubectl exec $WPOD -- wget -T 3 -O - http://10.96.0.1:443 2>&1 | head -3

echo ""
echo "--- 测量方法核验3: Pod 内是否有默认路由 ---"
kubectl exec $WPOD -- ip route 2>&1

echo ""
echo "--- 测量方法核验4: 用 nc 测跨节点 TCP（排除 ICMP 被禁）---"
kubectl exec $WPOD -- sh -c 'nc -l -p 9999 >/dev/null 2>&1 &' 2>&1
sleep 2
kubectl exec $CPOD -- sh -c "echo test | nc -w 3 $WIP 9999" 2>&1 && echo "TCP 跨节点通" || echo "TCP 跨节点不通"
EOS

echo ""
echo "########## 节点侧抓 vxlan 包 ##########"
ssh $SSHOPT k8s@$W1 'sudo -n bash -s' <<'EOS' 2>&1
echo "--- w1 上抓 vxlan.calico 的 ICMP（5秒）---"
timeout 8 tcpdump -i vxlan.calico -c 10 -nn icmp 2>&1 | head -12 || echo "tcpdump 不可用或无包"
echo ""
echo "--- w1 上抓 enp1s0 的 UDP 4789 ---"
timeout 8 tcpdump -i enp1s0 -c 5 -nn udp port 4789 2>&1 | head -8 || echo "无包或tcpdump不可用"
EOS

echo ""
echo "########## 清理 ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl delete daemonset netprobe --ignore-not-found >/dev/null 2>&1
echo "已清理"
EOS
