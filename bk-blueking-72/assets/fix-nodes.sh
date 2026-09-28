#!/usr/bin/env bash
echo "=== 1. kind 节点容器状态 ==="
docker ps -a --format '{{.Names}}\t{{.Status}}' 2>/dev/null | grep -E 'calico' | sed 's/^/  /'

echo ""
echo "=== 2. 停掉的 worker 容器重启 ==="
for c in k8s-c1-calico-worker k8s-c1-calico-worker2; do
  st=$(docker inspect -f '{{.State.Status}}' $c 2>/dev/null)
  if [ "$st" != "running" ]; then
    echo "  $c 状态=$st  -> 启动"
    docker start $c 2>&1 | sed 's/^/    /'
  else
    echo "  $c 已在运行"
  fi
done

echo ""
echo "=== 3. 等 120s 让 kubelet 上报 ==="
sleep 120

echo ""
echo "=== 4. 复查节点 ==="
kubectl get nodes --no-headers 2>&1 | sed 's/^/  /'

echo ""
echo "=== 5. 复查 Terminating 残留 ==="
echo "  Terminating: $(kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3=="Terminating"' | wc -l)"
echo "  Pod 总数:    $(kubectl get pods -n blueking --no-headers 2>/dev/null | wc -l)"

echo ""
echo "=== 6. 内存 ==="
free -g | sed -n '1,2p' | sed 's/^/  /'
cat /proc/pressure/memory 2>/dev/null | sed 's/^/  /'
