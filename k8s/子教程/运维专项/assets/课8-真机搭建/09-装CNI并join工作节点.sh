#!/usr/bin/env bash
set -o pipefail

CP1=192.168.122.19
W1=192.168.122.54
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

echo "########## [阶段1] 配置 kubectl ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
set -e
mkdir -p /home/k8s/.kube
cp -i /etc/kubernetes/admin.conf /home/k8s/.kube/config
chown k8s:k8s /home/k8s/.kube/config
echo "kubeconfig 已配置"
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "--- 节点状态（CNI 前，应为 NotReady）---"
kubectl get nodes -o wide 2>&1
echo "--- 系统 Pod ---"
kubectl get pods -n kube-system -o wide 2>&1
EOS

echo ""
echo "########## [阶段2] 安装 Calico CNI ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
set -o pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "--- 下载 Calico manifest ---"
curl -fsSL -o /tmp/calico.yaml https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml 2>&1
echo "下载完成: $(ls -lh /tmp/calico.yaml | awk '{print $5}')"
grep -n 'CALICO_IPV4POOL_CIDR' -A2 /tmp/calico.yaml | head -6
echo "--- 应用 Calico ---"
kubectl apply -f /tmp/calico.yaml 2>&1 | tail -12
echo "apply exit=$?"
EOS

echo ""
echo "########## [阶段3] 等待 CNI 就绪 ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
export KUBECONFIG=/etc/kubernetes/admin.conf
for i in $(seq 1 24); do
  R=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  echo "第 $i 次探测: Ready=$R"
  [ "$R" = "True" ] && break
  sleep 10
done
echo "--- 最终节点状态 ---"
kubectl get nodes -o wide 2>&1
echo "--- kube-system Pod ---"
kubectl get pods -n kube-system -o wide 2>&1
EOS

echo ""
echo "########## [阶段4] worker 加入集群 ##########"
echo "--- 生成 join 命令 ---"
JOIN_CMD=$(ssh $SSHOPT k8s@$CP1 "sudo -n kubeadm token create --print-join-command 2>&1")
echo "JOIN: $JOIN_CMD"

ssh $SSHOPT k8s@$W1 "sudo -n $JOIN_CMD --ignore-preflight-errors=NumCPU,Mem" 2>&1 | tail -20
echo "join exit=$?"

echo ""
echo "########## [阶段5] 集群最终状态 ##########"
sleep 15
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "=== 节点 ==="
kubectl get nodes -o wide 2>&1
echo ""
echo "=== 全部 Pod ==="
kubectl get pods -A -o wide 2>&1
echo ""
echo "=== 集群信息 ==="
kubectl cluster-info 2>&1
EOS
