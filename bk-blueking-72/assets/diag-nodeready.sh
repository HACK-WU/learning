#!/usr/bin/env bash
echo "=== 1. 节点 NotReady 原因 ==="
kubectl get nodes -o wide --no-headers 2>&1 | sed 's/^/  /'
echo ""
for n in k8s-c1-calico-worker k8s-c1-calico-worker2; do
  echo "  --- $n conditions ---"
  kubectl describe node $n 2>/dev/null | sed -n '/Conditions:/,/Addresses:/p' | grep -E 'Ready|MemoryPressure|DiskPressure|PIDPressure|NetworkUnavailable' | sed 's/^/    /'
  echo "  --- $n events(近5条) ---"
  kubectl describe node $n 2>/dev/null | sed -n '/Events:/,$p' | tail -6 | sed 's/^/    /'
  echo ""
done

echo "=== 2. WSL 实际内存（关键：是不是宿主机把 WSL 掐了） ==="
free -g | sed -n '1,2p' | sed 's/^/  /'
echo "  --- PSI ---"
cat /proc/pressure/memory 2>/dev/null | sed 's/^/  /'
echo "  --- OOM 记录 ---"
dmesg 2>/dev/null | tail -20 | grep -i -E 'oom|kill' | sed 's/^/    /' || echo "    (dmesg 不可用)"

echo ""
echo "=== 3. kubelet 是否活着（节点内） ==="
docker ps --format '{{.Names}}\t{{.Status}}' 2>/dev/null | grep -E 'worker' | sed 's/^/  /'
