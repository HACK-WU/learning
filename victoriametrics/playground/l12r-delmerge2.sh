#!/bin/bash
# 遗留项 3 修正版：集群版 delete_series 必须带租户前缀
VM="http://localhost:8481"
INS="http://localhost:8480"

echo "=== [1] 正确的删除 URL 格式（带租户 7777） ==="
code=$(curl -s -o /dev/null -w "%{http_code}" "${VM}/delete_series/7777?match[]={__name__=\"l12r_delme\"}")
echo "  /delete_series/7777 -> HTTP ${code}"

echo ""
echo "=== [2] 删除前基线 ==="
echo -n "租户 7777 系列数: "; curl -s "${VM}/select/7777/prometheus/api/v1/series/count"; echo ""
echo -n "export 字节数: "
curl -s -G "${VM}/select/7777/prometheus/api/v1/export" --data-urlencode 'match[]={__name__="l12r_delme"}' | wc -c
echo "--- 目录大小（KB） ---"
S1_0=$(docker exec vmstorage-learn du -sk /storage/data 2>/dev/null | cut -f1)
S2_0=$(docker exec vmstorage-learn2 du -sk /storage/data 2>/dev/null | cut -f1)
echo "  storage1=${S1_0}K  storage2=${S2_0}K"

echo ""
echo "=== [3] 执行删除 ==="
DEL_START=$(date +%s%N)
curl -s "${VM}/delete_series/7777?match[]={__name__=\"l12r_delme\"}" -w "  HTTP %{http_code}\n"
DEL_END=$(date +%s%N)
echo "  耗时: $(( (DEL_END-DEL_START)/1000000 )) ms"

echo ""
echo "=== [4] 删除后立即核验（2 秒） ==="
sleep 2
echo -n "租户 7777 系列数（预期不降，因含墓碑）: "; curl -s "${VM}/select/7777/prometheus/api/v1/series/count"; echo ""
echo -n "export 剩余字节数（应为 0）: "
curl -s -G "${VM}/select/7777/prometheus/api/v1/export" --data-urlencode 'match[]={__name__="l12r_delme"}' | wc -c

echo ""
echo "=== [5] 观察自动回收 60 秒 ==="
for t in 10 20 30 45 60; do
  sleep 10
  s1=$(docker exec vmstorage-learn du -sk /storage/data 2>/dev/null | cut -f1)
  s2=$(docker exec vmstorage-learn2 du -sk /storage/data 2>/dev/null | cut -f1)
  am=$(curl -s "http://localhost:8482/metrics" | grep -E 'vm_merges_total\{type="storage/big"\}' | awk '{print $2}')
  echo "  t=${t}s  storage1=${s1}K(Δ$((s1-S1_0)))  storage2=${s2}K(Δ$((s2-S2_0)))  big_merges_total=${am}"
done

echo ""
echo "=== [6] 手动触发 force_merge（仅 vmstorage 端点有效） ==="
echo "--- 触发前 ---"
B1=$(docker exec vmstorage-learn du -sk /storage/data 2>/dev/null | cut -f1)
B2=$(docker exec vmstorage-learn2 du -sk /storage/data 2>/dev/null | cut -f1)
echo "  storage1=${B1}K  storage2=${B2}K"
FM_START=$(date +%s%N)
curl -s -X POST "http://localhost:8482/internal/force_merge" -w "  8482 -> HTTP %{http_code}\n"
curl -s -X POST "http://localhost:8492/internal/force_merge" -w "  8492 -> HTTP %{http_code}\n"
FM_END=$(date +%s%N)
echo "  请求耗时: $(( (FM_END-FM_START)/1000000 )) ms"

echo ""
echo "=== [7] force_merge 后采样（观察合并是否真的回收空间） ==="
for t in 3 8 15 30 60; do
  sleep $((t==3 ? 3 : (t==8 ? 5 : (t==15 ? 7 : (t==30 ? 15 : 30)))))
  s1=$(docker exec vmstorage-learn du -sk /storage/data 2>/dev/null | cut -f1)
  s2=$(docker exec vmstorage-learn2 du -sk /storage/data 2>/dev/null | cut -f1)
  am=$(curl -s "http://localhost:8482/metrics" | grep -E 'vm_merges_total\{type="storage/big"\}' | awk '{print $2}')
  echo "  t=${t}s  storage1=${s1}K(Δ$((s1-B1)))  storage2=${s2}K(Δ$((s2-B2)))  big_merges_total=${am}"
done

echo ""
echo "=== [8] force_merge 是否真的删除了数据（export 复核） ==="
curl -s -G "${VM}/select/7777/prometheus/api/v1/export" --data-urlencode 'match[]={__name__="l12r_delme"}' | wc -c
echo "--- 租户 7777 系列数终值 ---"
curl -s "${VM}/select/7777/prometheus/api/v1/series/count"; echo ""
