#!/usr/bin/env bash
echo "=== 1. 所有 kind 容器内存占用（谁在吃） ==="
docker stats --no-stream --format '{{.Name}}\t{{.MemUsage}}' 2>/dev/null | sed 's/^/  /'

echo ""
echo "=== 2. WSL 宿主进程 TOP15 ==="
ps -eo rss,comm --sort=-rss --no-headers 2>/dev/null | head -15 | awk '{printf "  %6.2f GiB  %s\n", $1/1024/1024, $2}'

echo ""
echo "=== 3. WSL 宿主 java 进程明细（java 是大头，看是谁） ==="
ps -eo rss,pid,args --sort=-rss --no-headers 2>/dev/null | grep '[j]ava' | head -8 | \
  awk '{printf "  %6.2f GiB  pid=%s  %.90s\n", $1/1024/1024, $2, $3" "$4" "$5}'

echo ""
echo "=== 4. 非 blueking 命名空间（历史遗留） ==="
kubectl get ns --no-headers 2>/dev/null | awk '{print "  "$1}' | sed 's/^/  /'
echo ""
for ns in monitoring default kube-system; do
  c=$(kubectl get pods -n $ns --no-headers 2>/dev/null | wc -l)
  [ "$c" -gt 0 ] && echo "  ns=$ns Pod数=$c"
done

echo ""
echo "=== 5. monitoring ns 明细 ==="
kubectl get pods -n monitoring --no-headers 2>/dev/null | head -10 | sed 's/^/  /'
