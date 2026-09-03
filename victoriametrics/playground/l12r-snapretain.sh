#!/bin/bash
# 遗留项 1：快照长期保留对磁盘空间回收的定量影响
set -u
docker rm -f vm-l12r-snap 2>/dev/null >/dev/null
docker volume rm l12r_snap_vol 2>/dev/null >/dev/null
docker volume create l12r_snap_vol >/dev/null

echo "=== [1] 启动隔离单节点 ==="
docker run -d --name vm-l12r-snap --network host \
  -v l12r_snap_vol:/victoria-metrics-data \
  victoriametrics/victoria-metrics:v1.151.0 \
  -storageDataPath=/victoria-metrics-data \
  -retentionPeriod=1d \
  -httpListenAddr=:18501 >/dev/null 2>&1
sleep 4
V="http://localhost:18501"
curl -s -o /dev/null -w "  health -> HTTP %{http_code}\n" "${V}/health"

size() { docker exec vm-l12r-snap du -sk /victoria-metrics-data 2>/dev/null | cut -f1; }
smallsz() { docker exec vm-l12r-snap du -sk /victoria-metrics-data/data/small 2>/dev/null | cut -f1; }
snapcount() { docker exec vm-l12r-snap sh -c "ls /victoria-metrics-data/snapshots/ 2>/dev/null | wc -l"; }

echo ""
echo "=== [2] 灌入两批数据：to_delete（待删） + to_keep（保留） ==="
NOW=$(date +%s)
: > /tmp/l12r_sp.txt
for s in $(seq 0 2999); do
  for i in $(seq 0 9); do
    ts=$(( (NOW - 300 + i*30) * 1000 ))
    echo "l12r_sdel{sid=\"${s}\",idx=\"${i}\"} $((s+i)) ${ts}" >> /tmp/l12r_sp.txt
  done
done
for s in $(seq 0 2999); do
  for i in $(seq 0 9); do
    ts=$(( (NOW - 300 + i*30) * 1000 ))
    echo "l12r_skeep{sid=\"${s}\",idx=\"${i}\"} $((s+i)) ${ts}" >> /tmp/l12r_sp.txt
  done
done
echo "  payload 行数: $(wc -l < /tmp/l12r_sp.txt)"
curl -s -X POST --data-binary @/tmp/l12r_sp.txt "${V}/api/v1/import/prometheus" -w "  HTTP %{http_code}\n"
sleep 10

echo ""
echo "=== [3] 基线（快照前） ==="
S_BASE=$(size)
echo "  总大小=${S_BASE}K  small=$(smallsz)K  快照数=$(snapcount)"

echo ""
echo "=== [4] 创建快照（模拟\"长期保留\"） ==="
SNAP=$(curl -s "${V}/snapshot/create" | grep -o '"snapshot":"[^"]*"' | cut -d'"' -f4)
echo "  快照名: ${SNAP}"
sleep 2
S_SNAP=$(size)
echo "  建快照后: ${S_SNAP}K  Δ=$((S_SNAP-S_BASE))K  ← 硬链接，几乎不占空间"
echo "  快照数=$(snapcount)"

echo ""
echo "=== [5] 在快照存在的情况下删除数据 ==="
curl -s -X POST -G "${V}/api/v1/admin/tsdb/delete_series" \
  --data-urlencode 'match[]={__name__="l12r_sdel"}' -w "  delete HTTP %{http_code}\n"
sleep 2
echo -n "  export l12r_sdel 剩余: "; curl -s -G "${V}/api/v1/export" --data-urlencode 'match[]={__name__="l12r_sdel"}' | wc -c
echo -n "  export l12r_skeep（应完好）: "; curl -s -G "${V}/api/v1/export" --data-urlencode 'match[]={__name__="l12r_skeep"}' | wc -c

echo ""
echo "=== [6] 关键：快照仍在时触发 force_merge ==="
B1=$(size)
echo "  触发前: ${B1}K  small=$(smallsz)K  快照数=$(snapcount)"
curl -s -X POST "${V}/internal/force_merge" -w "  force_merge HTTP %{http_code}\n"
for i in 1 2 3 5 8; do
  sleep $((i==1 ? 1 : (i==2 ? 1 : (i==3 ? 1 : (i==5 ? 2 : 3)))))
  echo "    +${i}s: 总=$(size)K Δ=$(( $(size) - B1 ))K  small=$(smallsz)K"
done
A_SNAP=$(size)
echo "  【快照存在时】回收量: $((A_SNAP-B1))K"

echo ""
echo "=== [7] 决定性对照：删除快照后再 force_merge ==="
curl -s "${V}/snapshot/delete?snapshot=${SNAP}" -w "  删除快照 HTTP %{http_code}\n"
sleep 2
echo "  删快照后: $(size)K  快照数=$(snapcount)"
B2=$(size)
curl -s -X POST "${V}/internal/force_merge" -w "  force_merge HTTP %{http_code}\n"
for i in 1 2 3 5 8; do
  sleep $((i==1 ? 1 : (i==2 ? 1 : (i==3 ? 1 : (i==5 ? 2 : 3)))))
  echo "    +${i}s: 总=$(size)K Δ=$(( $(size) - B2 ))K  small=$(smallsz)K"
done
A_NOSNAP=$(size)
echo "  【快照删除后】回收量: $((A_NOSNAP-B2))K"

echo ""
echo "=== [8] 结论汇总 ==="
echo "  基线（删前）      : ${S_BASE}K"
echo "  建快照后          : ${S_SNAP}K  (Δ$((S_SNAP-S_BASE))K)"
echo "  删数据+快照仍在   : ${A_SNAP}K  (相对删前 $((A_SNAP-B1))K)"
echo "  删快照后再合并    : ${A_NOSNAP}K  (再释 $((A_NOSNAP-B2))K)"
echo "  全程净变化        : $((A_NOSNAP-S_BASE))K"
echo ""
echo -n "  最终 l12r_skeep 完好: "
curl -s -G "${V}/api/v1/export" --data-urlencode 'match[]={__name__="l12r_skeep"}' | wc -c
echo -n "  最终序列数: "; curl -s "${V}/api/v1/series/count"; echo ""
echo "  rows_deleted: "; curl -s "${V}/metrics" | grep -E "vm_rows_deleted_total" | head -5
