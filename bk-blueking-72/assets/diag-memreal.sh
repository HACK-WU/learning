#!/usr/bin/env bash
echo "=== 1. 删除动作是否真的生效（replicas 是否已为0） ==="
for d in bk-monitor-alarm-detect bk-monitor-alarm-trigger bk-nodeman-backend-common-worker bkiam-saas-worker; do
  r=$(kubectl get deploy -n blueking $d -o jsonpath='{.spec.replicas}/{.status.replicas}' 2>/dev/null)
  echo "  $d spec_ready=$r"
done

echo ""
echo "=== 2. 这些 Pod 的容器在宿主机(Docker)层面是否还在跑 ==="
docker stats --no-stream --format '{{.Name}}\t{{.MemUsage}}' 2>/dev/null | \
  grep -E 'alarm-detect|alarm-trigger|nodeman-backend-common|bkiam-saas-worker' | head -8 | sed 's/^/  /'
echo "  (空=容器已真删，有值=还占内存)"

echo ""
echo "=== 3. docker 容器总数与总内存 ==="
docker ps -q 2>/dev/null | wc -l | sed 's/^/  容器数: /'
docker stats --no-stream --format '{{.MemUsage}}' 2>/dev/null | \
  awk -F'[ /]+' '{gsub(/MiB/,"",$1); s+=$1} END{printf "  容器内存合计: %.2f GiB\n", s/1024}'

echo ""
echo "=== 4. WSL 内存去向 ==="
free -g | sed -n '1,2p' | sed 's/^/  /'
echo "  --- slab/内核 ---"
grep -E 'Slab|KernelStack|PageTables' /proc/meminfo 2>/dev/null | sed 's/^/  /'

echo ""
echo "=== 5. 真正的内存大头进程 ==="
ps -eo rss,comm --sort=-rss 2>/dev/null | head -12 | awk '{printf "  %.1f GiB  %s\n", $1/1024/1024, $2}'
