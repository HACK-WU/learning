#!/bin/bash
# 遗留项 3 精修：确定 force_merge 的回收延迟窗口；并测 -finalMergeDelay 相关行为
set -u
V="http://localhost:18500"
size() { docker exec vm-l12r-del du -sk /victoria-metrics-data 2>/dev/null | cut -f1; }
smallsz() { docker exec vm-l12r-del du -sk /victoria-metrics-data/data/small 2>/dev/null | cut -f1; }

echo "=== [A] 重建一批数据（保持同一指标名，便于复用） ==="
NOW=$(date +%s)
: > /tmp/l12r_p2.txt
for s in $(seq 0 2999); do
  for i in $(seq 0 9); do
    ts=$(( (NOW - 300 + i*30) * 1000 ))
    echo "l12r_delme2{sid=\"${s}\",idx=\"${i}\"} $((s+i)) ${ts}" >> /tmp/l12r_p2.txt
  done
done
curl -s -X POST --data-binary @/tmp/l12r_p2.txt "${V}/api/v1/import/prometheus" -w "  HTTP %{http_code}\n"
sleep 10
S0=$(size); SM0=$(smallsz)
echo "  基线: 总=${S0}K  small=${SM0}K"

echo ""
echo "=== [B] 删除并以 1 秒粒度测回收延迟 ==="
curl -s -X POST -G "${V}/api/v1/admin/tsdb/delete_series" \
  --data-urlencode 'match[]={__name__="l12r_delme2"}' -w "  delete HTTP %{http_code}\n"
sleep 2
echo -n "  export 剩余: "; curl -s -G "${V}/api/v1/export" --data-urlencode 'match[]={__name__="l12r_delme2"}' | wc -c

echo "  --- 删除后自动观察 20 秒（1 秒粒度前 10 秒） ---"
for i in $(seq 1 10); do
  sleep 1
  echo "    删除后 ${i}s: 总=$(size)K small=$(smallsz)K"
done

echo ""
echo "=== [C] force_merge 后以 1 秒粒度精确计时 ==="
B=$(size)
T0=$(date +%s%N)
curl -s -X POST "${V}/internal/force_merge" -w "  force_merge HTTP %{http_code}\n"
for i in $(seq 1 10); do
  sleep 1
  T1=$(date +%s%N)
  echo "    +$(( (T1-T0)/1000000 ))ms: 总=$(size)K (Δ$(( $(size) - B ))K) small=$(smallsz)K"
done

echo ""
echo "=== [D] 分区终态 ==="
docker exec vm-l12r-del sh -c "du -sk /victoria-metrics-data/data/* 2>/dev/null"

echo ""
echo "=== [E] 关键对照：没有删除数据时 force_merge 会怎样 ==="
: > /tmp/l12r_p3.txt
NOW=$(date +%s)
for s in $(seq 0 999); do
  for i in $(seq 0 9); do
    ts=$(( (NOW - 300 + i*30) * 1000 ))
    echo "l12r_keepme{sid=\"${s}\",idx=\"${i}\"} $((s+i)) ${ts}" >> /tmp/l12r_p3.txt
  done
done
curl -s -X POST --data-binary @/tmp/l12r_p3.txt "${V}/api/v1/import/prometheus" -w "  HTTP %{http_code}\n"
sleep 10
C0=$(size)
echo "  写入后: ${C0}K"
curl -s -X POST "${V}/internal/force_merge" -w "  force_merge HTTP %{http_code}\n"
sleep 5
C1=$(size)
echo "  force_merge 后: ${C1}K  Δ=$((C1-C0))K   ← 未删数据的合并不应显著释空间"
echo -n "  l12r_keepme 仍可查: "
curl -s -G "${V}/api/v1/export" --data-urlencode 'match[]={__name__="l12r_keepme"}' | wc -c

echo ""
echo "=== [F] forceMerge 相关内部指标全量 ==="
curl -s "${V}/metrics" | grep -iE "vm_merge|vm_deleted|vm_force_merge|vm_rows_deleted|vm_tombstone" | head -20
