#!/usr/bin/env bash
echo "=== 1. kind 节点容器 ==="
docker ps -a --format '{{.Names}}\t{{.Status}}' 2>/dev/null | grep calico | sed 's/^/  /'

echo ""
echo "=== 2. 启动 calico 集群容器 ==="
for c in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  st=$(docker inspect -f '{{.State.Status}}' $c 2>/dev/null)
  if [ "$st" != "running" ]; then
    echo "  $c ($st) -> start"
    docker start $c >/dev/null 2>&1 && echo "    started" || echo "    FAILED"
  else
    echo "  $c already running"
  fi
done

echo ""
echo "=== 3. 等 100s 让 kubelet 注册 ==="
sleep 100

echo ""
echo "=== 4. 节点 ==="
kubectl get nodes --no-headers 2>&1 | sed 's/^/  /'

echo ""
echo "=== 5. blueking Pod 状态汇总 ==="
T=$(kubectl get pods -n blueking --no-headers 2>/dev/null | wc -l)
R=$(kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3=="Running"' | wc -l)
T_=$(kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3=="Terminating"' | wc -l)
C=$(kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3=="CrashLoopBackOff"' | wc -l)
P=$(kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3=="Pending"' | wc -l)
echo "  总数=$T  Running=$R  Terminating=$T_  CrashLoop=$C  Pending=$P"

echo ""
echo "=== 6. 内存 ==="
free -g | sed -n '1,2p' | sed 's/^/  /'
