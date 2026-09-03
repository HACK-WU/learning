#!/bin/bash
set -u
V="http://localhost:18500"
size() { docker exec vm-l12r-del du -sk /victoria-metrics-data 2>/dev/null | cut -f1; }

echo "=== [1] 确认容器与数据仍在 ==="
curl -s -o /dev/null -w "  health -> HTTP %{http_code}\n" "${V}/health"
S0=$(size)
echo "  基线大小: ${S0}K"
echo -n "  序列数: "; curl -s "${V}/api/v1/series/count"; echo ""

echo ""
echo "=== [2] 用 --data-urlencode 正确编码 match[] 执行删除 ==="
D0=$(date +%s%N)
curl -s -X POST -G "${V}/api/v1/admin/tsdb/delete_series" \
  --data-urlencode 'match[]={__name__="l12r_delme"}' -w "  HTTP %{http_code}\n"
D1=$(date +%s%N)
echo "  耗时: $(( (D1-D0)/1000000 )) ms"

echo ""
echo "=== [3] 删除后立即核验 ==="
sleep 2
echo -n "  export 剩余字节数（应为 ~0）: "
curl -s -G "${V}/api/v1/export" --data-urlencode 'match[]={__name__="l12r_delme"}' | wc -c
echo -n "  序列数（含墓碑，预期不降）: "; curl -s "${V}/api/v1/series/count"; echo ""
echo "  分区明细:"; docker exec vm-l12r-del sh -c "du -sk /victoria-metrics-data/data/* 2>/dev/null"

echo ""
echo "=== [4] 自动回收观察 120 秒（盯 big_merges_total 跳变） ==="
MG0=$(curl -s "${V}/metrics" | grep -E 'vm_merges_total\{type="storage/big"\}' | awk '{print $2}')
echo "  起始 big_merges_total=${MG0}"
for t in 10 20 30 45 60 90 120; do
  sleep $((t==10 ? 10 : (t==20 ? 10 : (t==30 ? 10 : (t==45 ? 15 : (t==60 ? 15 : (t==90 ? 30 : 30)))))))
  s=$(size)
  mg=$(curl -s "${V}/metrics" | grep -E 'vm_merges_total\{type="storage/big"\}' | awk '{print $2}')
  sm=$(curl -s "${V}/metrics" | grep -E 'vm_merges_total\{type="storage/small"\}' | awk '{print $2}')
  echo "  t=${t}s  大小=${s}K  Δ=$((s-S0))K  big_merges_total=${mg}  small_merges_total=${sm}"
done

echo ""
echo "=== [5] 手动 force_merge ==="
B=$(size)
MB0=$(curl -s "${V}/metrics" | grep -E 'vm_merges_total\{type="storage/big"\}' | awk '{print $2}')
echo "  触发前: ${B}K   big_merges_total=${MB0}"
F0=$(date +%s%N)
curl -s -X POST "${V}/internal/force_merge" -w "  HTTP %{http_code}\n"
F1=$(date +%s%N)
echo "  请求耗时: $(( (F1-F0)/1000000 )) ms"

echo ""
echo "=== [6] force_merge 后密集采样 ==="
for t in 1 3 6 10 20 40 70 110 170; do
  sleep $((t==1 ? 1 : (t==3 ? 2 : (t==6 ? 3 : (t==10 ? 4 : (t==20 ? 10 : (t==40 ? 20 : (t==70 ? 30 : (t==110 ? 40 : 60)))))))))
  s=$(size)
  mg=$(curl -s "${V}/metrics" | grep -E 'vm_merges_total\{type="storage/big"\}' | awk '{print $2}')
  sm=$(curl -s "${V}/metrics" | grep -E 'vm_merges_total\{type="storage/small"\}' | awk '{print $2}')
  echo "  t=${t}s  大小=${s}K  Δ相对触发前=$((s-B))K  big_merges=${mg}  small_merges=${sm}"
done

echo ""
echo "=== [7] 终态分区明细 ==="
docker exec vm-l12r-del sh -c "du -sk /victoria-metrics-data/data/* 2>/dev/null"
echo -n "  export 剩余: "; curl -s -G "${V}/api/v1/export" --data-urlencode 'match[]={__name__="l12r_delme"}' | wc -c
echo -n "  序列数: "; curl -s "${V}/api/v1/series/count"; echo ""
