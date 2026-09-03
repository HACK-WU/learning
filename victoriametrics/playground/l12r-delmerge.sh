#!/bin/bash
# 遗留项 3：删除后后台合并触发空间回收的确切时机
# 工具：/internal/force_merge?authKey=... （单节点 vm-learn 未设 -forceMergeAuthKey，故无需 key）
VM="http://localhost:8481"   # 用集群 vmselect
INS="http://localhost:8480"

echo "=== [1] 确认 force_merge 端点在集群各组件上的可用性 ==="
for p in "8481/internal/force_merge" "8480/internal/force_merge" "8482/internal/force_merge" "8428/internal/force_merge"; do
  port="${p%%/*}"
  code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://localhost:${port}/internal/force_merge")
  echo "  localhost:${port}/internal/force_merge -> ${code}"
done

echo ""
echo "=== [2] 在集群上造一批待删除数据（300 条序列 x 20 样本） ==="
NOW=$(date +%s)
payload=""
for s in $(seq 0 299); do
  for i in $(seq 0 19); do
    ts=$(( (NOW - 600 + i*30) * 1000 ))
    payload="${payload}l12r_delme{sid=\"${s}\",idx=\"${i}\"} ${i} ${ts}\n"
  done
done
printf "${payload}" | curl -s -X POST --data-binary @- \
  "${INS}/insert/7777/prometheus/api/v1/import/prometheus" -w "  HTTP %{http_code}\n"
sleep 3

echo ""
echo "=== [3] 记录删除前基线 ==="
echo -n "租户 7777 系列数: "; curl -s "${VM}/select/7777/prometheus/api/v1/series/count"; echo ""
echo "--- 两个 storage 的数据目录大小 ---"
echo -n "storage1: "; docker exec vmstorage-learn du -sk /storage/data 2>/dev/null | cut -f1
echo -n "storage2: "; docker exec vmstorage-learn2 du -sk /storage/data 2>/dev/null | cut -f1
echo "--- 合并前 vm_active_merges / merge 计数 ---"
curl -s "http://localhost:8482/metrics" | grep -E "vm_active_merges|vm_merges_total|vm_deleted_metrics" | head -10

echo ""
echo "=== [4] 执行删除 ==="
DEL_START=$(date +%s%N)
curl -s "${VM}/delete_series?match[]={__name__=\"l12r_delme\"}" -w "  HTTP %{http_code}\n"
DEL_END=$(date +%s%N)
echo "delete_series 耗时: $(( (DEL_END-DEL_START)/1000000 )) ms"

echo ""
echo "=== [5] 删除后立刻采样（0 秒） ==="
sleep 2
echo -n "租户 7777 系列数（删除后）: "; curl -s "${VM}/select/7777/prometheus/api/v1/series/count"; echo ""
echo -n "export l12r_delme 样本数: "
curl -s -G "${VM}/select/7777/prometheus/api/v1/export" --data-urlencode 'match[]={__name__="l12r_delme"}' | wc -c
echo "--- 目录大小 ---"
echo -n "storage1: "; docker exec vmstorage-learn du -sk /storage/data 2>/dev/null | cut -f1
echo -n "storage2: "; docker exec vmstorage-learn2 du -sk /storage/data 2>/dev/null | cut -f1

echo ""
echo "=== [6] 等待 60 秒观察自动回收（课 12 曾等 60 秒未见） ==="
for t in 15 30 45 60; do
  sleep 15
  s1=$(docker exec vmstorage-learn du -sk /storage/data 2>/dev/null | cut -f1)
  s2=$(docker exec vmstorage-learn2 du -sk /storage/data 2>/dev/null | cut -f1)
  am=$(curl -s "http://localhost:8482/metrics" | grep 'vm_active_merges{type="storage/big"}' | awk '{print $2}')
  echo "  t=${t}s  storage1=${s1}K  storage2=${s2}K  active_merges(big)=${am}"
done

echo ""
echo "=== [7] 结论性一步：手动触发 force_merge ==="
echo "--- 触发前 ---"
echo -n "storage1: "; docker exec vmstorage-learn du -sk /storage/data 2>/dev/null | cut -f1
echo -n "storage2: "; docker exec vmstorage-learn2 du -sk /storage/data 2>/dev/null | cut -f1
FM_START=$(date +%s%N)
for port in 8482 8492; do
  curl -s -X POST "http://localhost:${port}/internal/force_merge" -w "  ${port} -> HTTP %{http_code}\n"
done
FM_END=$(date +%s%N)
echo "force_merge 请求耗时: $(( (FM_END-FM_START)/1000000 )) ms"

echo ""
echo "=== [8] force_merge 后持续采样 ==="
for t in 5 10 20 40 70; do
  sleep $((t == 5 ? 5 : t - prev))
  prev=$t
  s1=$(docker exec vmstorage-learn du -sk /storage/data 2>/dev/null | cut -f1)
  s2=$(docker exec vmstorage-learn2 du -sk /storage/data 2>/dev/null | cut -f1)
  echo "  t=${t}s  storage1=${s1}K  storage2=${s2}K"
done
