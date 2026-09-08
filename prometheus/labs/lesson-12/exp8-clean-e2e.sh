#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
P=http://localhost:19500
NET=l12net

q() { curl -s "$P/api/v1/query?query=$1" | python3 -c "
import json,sys
r=json.load(sys.stdin)['data']['result']
print(r[0]['value'][1] if r else 'empty')"; }
hs() { curl -s $P/api/v1/status/tsdb | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['headStats']['numSeries'])"; }
disk() { docker exec l12-prom sh -c "du -sk /prometheus 2>/dev/null | cut -f1"; }

echo "===== 重建干净环境 ====="
docker rm -f l12-prom l12-app 2>/dev/null || true
sudo rm -rf $D/data 2>/dev/null || rm -rf $D/data
mkdir -p $D/data
docker run -d --name l12-app --network $NET -e N_SERIES=20000 -e BASE_NAME=l12_series l12-app >/dev/null
docker run -d --name l12-prom --network $NET \
  -v $D/cfg:/cfg:ro -v $D/data:/prometheus -p 19500:9090 \
  prom/prometheus:v3.14.0 \
  --config.file=/cfg/prometheus-l12.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=1h \
  --web.enable-admin-api --web.enable-lifecycle >/dev/null

for i in $(seq 1 40); do
  if curl -sf $P/-/ready >/dev/null 2>&1; then echo "ready after ${i}s"; break; fi
  sleep 1
done
sleep 20   # 抓 4 轮

echo
echo "===== [A] 基线（app 在跑） ====="
echo "count(l12_series) = $(q 'count(l12_series)')"
echo "headSeries        = $(hs)"
echo "disk_kb           = $(disk)"

echo
echo "===== [B] 停 app（切断新数据） ====="
docker stop l12-app >/dev/null; echo "stopped"
sleep 8
echo "count = $(q 'count(l12_series)')   <- 应为 20000（历史数据仍在）"
echo "headSeries = $(hs)"

echo
echo "===== [C] 删除 ====="
curl -s -XPOST "$P/api/v1/admin/tsdb/delete_series" --data-urlencode 'match[]=l12_series' -w "HTTP=%{http_code}\n"
sleep 3
echo "count = $(q 'count(l12_series)')   <- 应 empty"
echo "headSeries = $(hs)"
echo "disk_kb（删后） = $(disk)"

echo
echo "===== [D] clean_tombstones ====="
curl -s -XPOST "$P/api/v1/admin/tsdb/clean_tombstones" -w "HTTP=%{http_code}\n"
sleep 3
echo "headSeries = $(hs)"
echo "disk_kb（清理后） = $(disk)"

echo
echo "===== [E] 重启：删除持久化了吗 ====="
docker restart l12-prom >/dev/null
for i in $(seq 1 40); do
  if curl -sf $P/-/ready >/dev/null 2>&1; then echo "ready after ${i}s"; break; fi
  sleep 1
done
sleep 5
echo "count = $(q 'count(l12_series)')   <- empty=持久化成功；20000=复活"
echo "headSeries = $(hs)"
echo "disk_kb = $(disk)"
