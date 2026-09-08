#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
P=http://localhost:19500

du_disk() { docker exec l12-prom sh -c "du -sk /prometheus 2>/dev/null | cut -f1"; }

echo "===== 删除前基线 ====="
echo "disk_kb = $(du_disk)"
curl -s $P/api/v1/status/tsdb | python3 -c "
import json,sys; d=json.load(sys.stdin)['data']['headStats']
print('headSeries =', d['numSeries'])"

echo
echo "===== [1] 删除序列（delete_series） ====="
DEL=$(curl -s -XPOST "$P/api/v1/admin/tsdb/delete_series" \
  --data-urlencode 'match[]=l12_series' -w "\nHTTP=%{http_code}")
echo "$DEL"

sleep 3
echo
echo "===== [2] 删除后立即看：序列数与磁盘 ====="
curl -s $P/api/v1/status/tsdb | python3 -c "
import json,sys; d=json.load(sys.stdin)['data']['headStats']
print('headSeries =', d['numSeries'])"
echo "disk_kb（删后，未清理）= $(du_disk)"

echo
echo "===== [3] 数据还能查到吗（tombstone 生效验证） ====="
echo -n "l12_series count: "
curl -s "$P/api/v1/query?query=count(l12_series)" | python3 -c "
import json,sys; r=json.load(sys.stdin)['data']['result']
print(r[0]['value'][1] if r else 'empty')"

echo
echo "===== [4] clean_tombstones ====="
echo -n "clean result: "
curl -s -XPOST "$P/api/v1/admin/tsdb/clean_tombstones" -w " HTTP=%{http_code}"; echo

sleep 3
echo
echo "===== [5] 清理后磁盘 ====="
echo "disk_kb（清理后）= $(du_disk)"
curl -s $P/api/v1/status/tsdb | python3 -c "
import json,sys; d=json.load(sys.stdin)['data']['headStats']
print('headSeries =', d['numSeries'])"
