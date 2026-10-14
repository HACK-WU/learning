#!/usr/bin/env bash
set -o pipefail

CP1=192.168.122.19
W1=192.168.122.54
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

echo "########## install-cni 失败根因 ##########"
ssh $SSHOPT k8s@$CP1 'sudo -n bash -s' <<'EOS' 2>&1
export KUBECONFIG=/etc/kubernetes/admin.conf
for POD in $(kubectl get pods -n kube-system -l k8s-app=calico-node -o jsonpath='{.items[*].metadata.name}'); do
  NODE=$(kubectl get pod -n kube-system $POD -o jsonpath='{.spec.nodeName}')
  echo "======== $POD (节点=$NODE) ========"
  echo "--- install-cni 容器日志 ---"
  kubectl logs -n kube-system $POD -c install-cni --tail=25 2>&1
  echo ""
done
EOS

echo ""
echo "########## 节点侧：CNI 目录与配置 ##########"
for NODE_IP in $CP1 $W1; do
echo "======== $NODE_IP ========"
ssh $SSHOPT k8s@$NODE_IP 'sudo -n bash -s' <<'EOS' 2>&1
echo "--- /opt/cni/bin ---"
ls /opt/cni/bin 2>&1 | head -10
echo ""
echo "--- /etc/cni/net.d ---"
ls -la /etc/cni/net.d 2>&1
echo ""
echo "--- CNI 配置文件内容 ---"
for f in /etc/cni/net.d/*.conf*; do [ -f "$f" ] && echo "== $f ==" && cat "$f"; done 2>&1 | head -30
echo ""
echo "--- 内存与负载 ---"
free -m | awk '/Mem:/ {print "total="$2"MB available="$7"MB"}'
uptime
EOS
done
