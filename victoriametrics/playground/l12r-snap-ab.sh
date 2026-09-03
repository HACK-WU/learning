#!/bin/bash
# 遗留项 1 严格对照：同一份数据，A 组带快照 / B 组不带快照，比较回收量
set -u
mk() {
  local name=$1 port=$2
  docker rm -f $name 2>/dev/null >/dev/null
  docker volume rm ${name}_vol 2>/dev/null >/dev/null
  docker volume create ${name}_vol >/dev/null
  docker run -d --name $name --network host \
    -v ${name}_vol:/victoria-metrics-data \
    victoriametrics/victoria-metrics:v1.151.0 \
    -storageDataPath=/victoria-metrics-data \
    -retentionPeriod=1d -httpListenAddr=:${port} >/dev/null 2>&1
}

echo "=== [1] 启动两个完全相同的实例 ==="
mk vm-l12r-A 18510
mk vm-l12r-B 18511
sleep 5
curl -s -o /dev/null -w "  A health -> %{http_code}\n" http://localhost:18510/health
curl -s -o /dev/null -w "  B health -> %{http_code}\n" http://localhost:18511/health

echo ""
echo "=== [2] 生成同一份 payload 并同时灌入两组 ==="
NOW=$(date +%s)
: > /tmp/l12r_ab.txt
for s in $(seq 0 2999); do
  for i in $(seq 0 9); do
    ts=$(( (NOW - 300 + i*30) * 1000 ))
    echo "l12r_abdel{sid=\"${s}\",idx=\"${i}\"} $((s+i)) ${ts}" >> /tmp/l12r_ab.txt
  done
done
for s in $(seq 0 2999); do
  for i in $(seq 0 9); do
    ts=$(( (NOW - 300 + i*30) * 1000 ))
    echo "l12r_abkeep{sid=\"${s}\",idx=\"${i}\"} $((s+i)) ${ts}" >> /tmp/l12r_ab.txt
  done
done
echo "  行数: $(wc -l < /tmp/l12r_ab.txt)"
curl -s -X POST --data-binary @/tmp/l12r_ab.txt "http://localhost:18510/api/v1/import/prometheus" -w "  A HTTP %{http_code}\n"
curl -s -X POST --data-binary @/tmp/l12r_ab.txt "http://localhost:18511/api/v1/import/prometheus" -w "  B HTTP %{http_code}\n"
sleep 12

szA() { docker exec vm-l12r-A du -sk /victoria-metrics-data 2>/dev/null | cut -f1; }
szB() { docker exec vm-l12r-B du -sk /victoria-metrics-data 2>/dev/null | cut -f1; }
smA() { docker exec vm-l12r-A du -sk /victoria-metrics-data/data/small 2>/dev/null | cut -f1; }
smB() { docker exec vm-l12r-B du -sk /victoria-metrics-data/data/small 2>/dev/null | cut -f1; }

echo ""
echo "=== [3] 基线（两组应基本一致） ==="
A0=$(szA); B0=$(szB)
echo "  A=${A0}K (small=$(smA)K)   B=${B0}K (small=$(smB)K)"

echo ""
echo "=== [4] A 组建快照，B 组不建 ==="
SNAP=$(curl -s http://localhost:18510/snapshot/create | grep -o '"snapshot":"[^"]*"' | cut -d'"' -f4)
echo "  A 快照: ${SNAP}"
sleep 2
echo "  A=${A0}K -> $(szA)K"

echo ""
echo "=== [5] 两组同时删除同一批数据 ==="
curl -s -X POST -G "http://localhost:18510/api/v1/admin/tsdb/delete_series" \
  --data-urlencode 'match[]={__name__="l12r_abdel"}' -w "  A delete HTTP %{http_code}\n"
curl -s -X POST -G "http://localhost:18511/api/v1/admin/tsdb/delete_series" \
  --data-urlencode 'match[]={__name__="l12r_abdel"}' -w "  B delete HTTP %{http_code}\n"
sleep 2

echo ""
echo "=== [6] 两组同时 force_merge ==="
curl -s -X POST "http://localhost:18510/internal/force_merge" -w "  A merge HTTP %{http_code}\n"
curl -s -X POST "http://localhost:18511/internal/force_merge" -w "  B merge HTTP %{http_code}\n"
sleep 8
A1=$(szA); B1=$(szB)
echo "  A（带快照）: ${A0}K -> ${A1}K   Δ=$((A1-A0))K   small=$(smA)K"
echo "  B（无快照）: ${B0}K -> ${B1}K   Δ=$((B1-B0))K   small=$(smB)K"

echo ""
echo "=== [7] A 组删除快照后再合并 ==="
curl -s "http://localhost:18510/snapshot/delete?snapshot=${SNAP}" -w "  A 删快照 HTTP %{http_code}\n"
sleep 2
A2=$(szA)
echo "  A 删快照后: ${A2}K  Δ相对删前=$((A2-A1))K"
curl -s -X POST "http://localhost:18510/internal/force_merge" -w "  A merge HTTP %{http_code}\n"
sleep 8
A3=$(szA)
echo "  A 再合并后: ${A3}K  small=$(smA)K"

echo ""
echo "=== [8] 对照结论 ==="
echo "  ┌──────────────┬─────────┬─────────┬─────────┐"
echo "  │ 阶段         │ A(带快照)│ B(无快照)│ 差异    │"
echo "  ├──────────────┼─────────┼─────────┼─────────┤"
echo "  │ 基线          │ ${A0}K │ ${B0}K │ $((A0-B0))K │"
echo "  │ 删+合并后     │ ${A1}K │ ${B1}K │ $((A1-B1))K │"
echo "  │ 终态          │ ${A3}K │ ${B1}K │ $((A3-B1))K │"
echo "  └──────────────┴─────────┴─────────┴─────────┘"
echo ""
echo "  A 组净回收（基线→终态）: $((A3-A0))K"
echo "  B 组净回收（基线→终态）: $((B1-B0))K"
echo "  快照导致的额外占用（删+合并后差异）: $((A1-B1))K"

echo ""
echo "=== [9] 数据完整性复核 ==="
echo -n "  A 组 l12r_abkeep: "; curl -s -G "http://localhost:18510/api/v1/export" --data-urlencode 'match[]={__name__="l12r_abkeep"}' | wc -c
echo -n "  B 组 l12r_abkeep: "; curl -s -G "http://localhost:18511/api/v1/export" --data-urlencode 'match[]={__name__="l12r_abkeep"}' | wc -c
echo -n "  A 组 l12r_abdel : "; curl -s -G "http://localhost:18510/api/v1/export" --data-urlencode 'match[]={__name__="l12r_abdel"}' | wc -c
echo -n "  B 组 l12r_abdel : "; curl -s -G "http://localhost:18511/api/v1/export" --data-urlencode 'match[]={__name__="l12r_abdel"}' | wc -c
