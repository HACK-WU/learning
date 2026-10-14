#!/usr/bin/env bash
set -o pipefail

CP1=192.168.122.19
W1=192.168.122.54
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

echo "########## 精确同步抓包 ##########"

# 步骤1：先在两节点后台启动 tcpdump
echo "--- 启动 w1 抓包（后台）---"
ssh $SSHOPT k8s@$W1 "sudo -n nohup tcpdump -i any -nn -c 30 'host 10.244.71.72 or udp port 4789' > /tmp/w1.pcap.log 2>&1 &" 2>&1
echo "--- 启动 cp1 抓包（后台）---"
ssh $SSHOPT k8s@$CP1 "sudo -n nohup tcpdump -i any -nn -c 30 'host 10.244.228.71 or udp port 4789' > /tmp/cp1.pcap.log 2>&1 &" 2>&1
sleep 3
echo "抓包已启动"

# 步骤2：部署 Pod 并 ping
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
kubectl get pods -l app=netprobe -o wide 2>&1
WPOD=$(kubectl get pods -l app=netprobe -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{"\n"}{end}' | awk '$2=="k8s-w1"{print $1}')
CPOD=$(kubectl get pods -l app=netprobe -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{"\n"}{end}' | awk '$2=="k8s-cp1"{print $1}')
WIP=$(kubectl get pod $WPOD -o jsonpath='{.status.podIP}')
CIP=$(kubectl get pod $CPOD -o jsonpath='{.status.podIP}')
echo "cp1_pod=$CPOD($CIP)  w1_pod=$WPOD($WIP)"
echo "=== 开始 ping ==="
kubectl exec $CPOD -- ping -c 5 -W 2 $WIP 2>&1 | tail -5
echo "=== 同时：从 cp1 宿主机 ping w1 的 Pod IP（测宿主机层面）==="
EOS

# 步骤3：cp1 宿主机直接 ping w1 的 Pod IP
echo ""
echo "--- cp1 宿主机 ping w1 Pod IP ---"
ssh $SSHOPT k8s@$CP1 "sudo -n ping -c 3 -W 2 10.244.228.71 2>&1 | tail -4" 2>&1

sleep 3

echo ""
echo "########## 抓包结果 ##########"
echo "======== cp1 侧 ========"
ssh $SSHOPT k8s@$CP1 "sudo -n cat /tmp/cp1.pcap.log 2>&1" | head -20
echo ""
echo "======== w1 侧 ========"
ssh $SSHOPT k8s@$W1 "sudo -n cat /tmp/w1.pcap.log 2>&1" | head -20

echo ""
echo "########## 清理 ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl delete daemonset netprobe --ignore-not-found >/dev/null 2>&1
echo "已清理"
EOS
