#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
P=http://localhost:19500

q() { curl -s "$P/api/v1/query?query=$1" | python3 -c "
import json,sys
r=json.load(sys.stdin)['data']['result']
print(r[0]['value'][1] if r else 'empty')"; }
hs() { curl -s $P/api/v1/status/tsdb | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['headStats']['numSeries'])"; }

echo "===== Step 0: 停掉 app，切断新数据源 ====="
docker stop l12-app >/dev/null; echo "l12-app stopped"
sleep 8   # 等最后一次抓取 + staleness

echo "count(l12_series) = $(q 'count(l12_series)')"
echo "headSeries        = $(hs)"

echo
echo "===== Step 1: 删除 ====="
curl -s -XPOST "$P/api/v1/admin/tsdb/delete_series" --data-urlencode 'match[]=l12_series' -w "HTTP=%{http_code}\n"
sleep 3
echo "删除后 count = $(q 'count(l12_series)')"
echo "删除后 headSeries = $(hs)"

echo
echo "===== Step 2: 重启，看是否复活 ====="
docker restart l12-prom >/dev/null
for i in $(seq 1 40); do
  if curl -sf $P/-/ready >/dev/null 2>&1; then echo "ready after ${i}s"; break; fi
  sleep 1
done
sleep 5
echo "重启后 count = $(q 'count(l12_series)')"
echo "重启后 headSeries = $(hs)"
