#!/bin/bash
# 课 12 实验 11：迁移路径 —— Prometheus -> VM 的历史数据迁移
# 用官方 vmctl 做 remote-read 迁移与 prometheus snapshot 迁移
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
BASE=/mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428
PROM=http://localhost:9090

echo "===== [1] Prometheus 源端现状 ====="
echo "-- Prometheus 版本与健康 --"
curl -s -o /dev/null -w "  /-/healthy HTTP=%{http_code}\n" $PROM/-/healthy
curl -s $PROM/api/v1/status/buildinfo | head -c 200; echo
echo "-- Prometheus 数据目录 --"
docker inspect prom-learn --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'
echo "-- Prometheus 有多少序列 --"
curl -s "$PROM/api/v1/label/__name__/values" | python3 -c "import sys,json;d=json.load(sys.stdin)['data'];print('  指标名数 =',len(d))"
echo "-- Prometheus 数据目录大小 --"
docker exec prom-learn sh -c "du -sk /prometheus 2>/dev/null | tail -1"

echo ""
echo "===== [2] 拉 vmctl 镜像 ====="
timeout 300 docker pull victoriametrics/vmctl:v1.151.0 2>&1 | tail -2

echo ""
echo "===== [3] 迁移方式 A：vmctl remote-read（从运行中的 Prometheus 拉历史数据） ====="
echo "-- 先建一个专用租户做迁移目标，避免污染 tenant 0 --"
echo "-- 探测 remote read 端点 --"
curl -s -o /dev/null -w "  prom remote_read HTTP=%{http_code}\n" "$PROM/api/v1/read"

echo "-- 执行 vmctl remote-read 迁移（时间范围：最近 2 小时） --"
START=$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)
END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "  时间范围: $START ~ $END"

docker run --rm --network vm-cluster-net \
  victoriametrics/vmctl:v1.151.0 \
  remote-read \
  --vm-addr=http://vminsert-learn:8480/insert/0/prometheus \
  --vm-concurrency=4 \
  --remote-read-src-addr=http://prom-learn:9090 \
  --remote-read-filter-time-start=$START \
  --remote-read-filter-time-end=$END \
  --remote-read-step=60s 2>&1 | tail -25

echo ""
echo "===== [4] 迁移结果核对 ====="
echo "-- VM 侧现在有多少指标名 --"
curl -s "$VM/api/v1/label/__name__/values" | python3 -c "import sys,json;d=json.load(sys.stdin)['data'];print('  VM 指标名数 =',len(d))"
echo "-- 序列总数 --"
curl -s $VM/api/v1/series/count; echo
