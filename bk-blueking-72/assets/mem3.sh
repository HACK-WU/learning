#!/usr/bin/env bash
echo "=== A. METRICS-SERVER STATUS ==="
kubectl get pods -A --no-headers 2>/dev/null | grep -i metrics | sed 's/^/  /'
kubectl apiservices 2>/dev/null | grep metrics | sed 's/^/  /'
echo "  (empty = metrics-server not installed)"

echo ""
echo "=== B. NODE INFO (is this local/docker?) ==="
kubectl get nodes -o wide 2>/dev/null | sed 's/^/  /'
echo ""
kubectl get nodes -o json 2>/dev/null | grep -oE '"(containerRuntimeVersion|kubeletVersion|osImage)":"[^"]*"' | sort -u | sed 's/^/  /'

echo ""
echo "=== C. NODE ALLOCATABLE (capacity) ==="
kubectl get nodes --no-headers 2>/dev/null | awk '{print "  "$1}'
kubectl describe nodes 2>/dev/null | grep -E '^  (memory|cpu):' | head -12 | sed 's/^/  /'
kubectl describe nodes 2>/dev/null | grep -B2 -A1 'Capacity:' | head -30 | sed 's/^/  /'

echo ""
echo "=== D. PER-NODE ALLOCATED (requests vs limits) ==="
for n in $(kubectl get nodes --no-headers 2>/dev/null | awk '{print $1}'); do
  echo "  node=$n"
  kubectl describe node "$n" 2>/dev/null | grep -A6 'Allocated resources' | grep -E 'cpu|memory' | sed 's/^/    /'
done

echo ""
echo "=== E. TOP MEMORY REQUESTS (which workloads ask most) ==="
kubectl get pods -n blueking -o json 2>/dev/null | grep -oE '"name":"[a-z0-9-]+","(requests|limits)".{0,200}' | head -3
echo "  --- via describe: sum requests per deployment ---"
kubectl get pods -n blueking --no-headers 2>/dev/null | awk '{print $1}' | head -0

echo ""
echo "=== F. HOST MEMORY (if we can see it) ==="
free -m 2>/dev/null | sed 's/^/  /'
echo "  --- cgroup limit ---"
cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null | sed 's/^/  /'
