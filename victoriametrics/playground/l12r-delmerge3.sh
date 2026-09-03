#!/bin/bash
# 遗留项 3 终极版：在隔离的单节点容器上做，排除背景写入噪声
# 关键：/internal/force_merge 只在 vmstorage / 单节点上有效（vmselect、vminsert 返 400）
set -u
docker rm -f vm-l12r-del 2>/dev/null >/dev/null
docker volume rm l12r_del_vol 2>/dev/null >/dev/null
docker volume create l12r_del_vol >/dev/null

echo "=== [1] 启动隔离单节点（无抓取任务，零背景写入） ==="
docker run -d --name vm-l12r-del --network host \
  -v l12r_del_vol:/victoria-metrics-data \
  victoriametrics/victoria-metrics:v1.151.0 \
  -storageDataPath=/victoria-metrics-data \
  -retentionPeriod=1d \
  -httpListenAddr=:18500 \
  -search.disableAutoCacheReset >/dev/null 2>&1
sleep 4
curl -s -o /dev/null -w "  health -> HTTP %{http_code}\n" http://localhost:18500/health

V="http://localhost:18500"
size() { docker exec vm-l12r-del du -sk /victoria-metrics-data 2>/dev/null | cut -f1; }

echo ""
echo "=== [2] 灌入 6000 条序列 x 10 样本（纯静态，灌完不再写） ==="
NOW=$(date +%s)
: > /tmp/l12r_del_payload.txt
for s in $(seq 0 5999); do
  for i in $(seq 0 9); do
    ts=$(( (NOW - 300 + i*30) * 1000 ))
    echo "l12r_delme{sid=\"${s}\",idx=\"${i}\"} $((s+i)) ${ts}" >> /tmp/l12r_del_payload.txt
  done
done
echo "  payload 行数: $(wc -l < /tmp/l12r_del_payload.txt)"
docker cp /tmp/l12r_del_payload.txt vm-l12r-del:/tmp/p.txt >/dev/null
docker exec vm-l12r-del sh -c "curl -s -X POST --data-binary @/tmp/p.txt http://localhost:18500/api/v1/import/prometheus -w 'HTTP %{http_code}\n'"

echo ""
echo "=== [3] 等待落盘稳定后取基线 ==="
sleep 8
S0=$(size)
echo "  基线目录大小: ${S0}K"
echo -n "  序列数: "; curl -s "${V}/api/v1/series/count"; echo ""
echo -n "  export 字节数: "; curl -s -G "${V}/api/v1/export" --data-urlencode 'match[]={__name__="l12r_delme"}' | wc -c

echo ""
echo "=== [4] 删除 ==="
D0=$(date +%s%N)
curl -s "${V}/api/v1/admin/tsdb/delete_series?match[]={__name__=\"l12r_delme\"}" -w "  HTTP %{http_code}\n"
D1=$(date +%s%N)
echo "  耗时: $(( (D1-D0)/1000000 )) ms"

echo ""
echo "=== [5] 删除后自动回收观察 90 秒 ==="
sleep 2
echo -n "  删除后 export 字节数: "; curl -s -G "${V}/api/v1/export" --data-urlencode 'match[]={__name__="l12r_delme"}' | wc -c
echo -n "  删除后序列数: "; curl -s "${V}/api/v1/series/count"; echo ""
for t in 10 20 30 45 60 90; do
  sleep $((t==10 ? 8 : (t==20 ? 10 : (t==30 ? 10 : (t==45 ? 15 : (t==60 ? 15 : 30))))))
  s=$(size)
  mg=$(curl -s "${V}/metrics" | grep -E 'vm_merges_total\{type="storage/big"\}' | awk '{print $2}')
  echo "  t=${t}s  大小=${s}K  Δ=$((s-S0))K  big_merges_total=${mg}"
done

echo ""
echo "=== [6] 手动 force_merge ==="
B=$(size)
echo "  触发前: ${B}K"
F0=$(date +%s%N)
curl -s -X POST "${V}/internal/force_merge" -w "  HTTP %{http_code}\n"
F1=$(date +%s%N)
echo "  请求耗时: $(( (F1-F0)/1000000 )) ms"

echo ""
echo "=== [7] force_merge 后采样（盯 big_merges_total 是否从 0 跳变） ==="
for t in 2 5 10 20 40 70 110; do
  sleep $((t==2 ? 2 : (t==5 ? 3 : (t==10 ? 5 : (t==20 ? 10 : (t==40 ? 20 : (t==70 ? 30 : 40)))))))
  s=$(size)
  mg=$(curl -s "${V}/metrics" | grep -E 'vm_merges_total\{type="storage/big"\}' | awk '{print $2}')
  echo "  t=${t}s  大小=${s}K  Δ相对触发前=$((s-B))K  big_merges_total=${mg}"
done

echo ""
echo "=== [8] 终态核验 ==="
echo -n "  export 剩余字节数: "; curl -s -G "${V}/api/v1/export" --data-urlencode 'match[]={__name__="l12r_delme"}' | wc -c
echo -n "  序列数: "; curl -s "${V}/api/v1/series/count"; echo ""
echo "--- data 目录分区明细 ---"
docker exec vm-l12r-del sh -c "du -sk /victoria-metrics-data/data/* 2>/dev/null"
