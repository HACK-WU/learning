#!/usr/bin/env bash
# VictoriaMetrics：单节点 + 最小集群（vmstorage/vminsert/vmselect 各 1）
set -euo pipefail
NET=l9net

echo "=== 1. 单节点 VM ==="
docker rm -f l9-vm-single 2>/dev/null || true
docker run -d --name l9-vm-single --network $NET -p 19420:8428 \
  victoriametrics/victoria-metrics:v1.151.0 \
  -storageDataPath=/vmdata -retentionPeriod=3d \
  -dedup.minScrapeInterval=5s >/dev/null
echo "l9-vm-single started (host :19420)"

echo
echo "=== 2. 最小集群 ==="
docker rm -f l9-vmstorage l9-vminsert l9-vmselect 2>/dev/null || true
docker run -d --name l9-vmstorage --network $NET \
  victoriametrics/vmstorage:v1.151.0-cluster \
  -storageDataPath=/vmdata -retentionPeriod=3d >/dev/null
echo "l9-vmstorage started"

docker run -d --name l9-vminsert --network $NET -p 19421:8480 \
  victoriametrics/vminsert:v1.151.0-cluster \
  -storageNode=l9-vmstorage:8400 >/dev/null
echo "l9-vminsert started (host :19421)"

docker run -d --name l9-vmselect --network $NET -p 19422:8481 \
  victoriametrics/vmselect:v1.151.0-cluster \
  -storageNode=l9-vmstorage:8401 \
  -dedup.minScrapeInterval=5s >/dev/null
echo "l9-vmselect started (host :19422)"

echo
echo "=== 3. 让两个 Thanos 副本也写一份到 VM（用于对比去重差异）==="
for i in 1 2; do
  case $i in
    1) url=http://l9-vm-single:8428/api/v1/write ;;
  esac
done

echo
echo "=== 4. 等待就绪 ==="
sleep 12
for c in l9-vm-single l9-vmstorage l9-vminsert l9-vmselect; do
  echo "  $c: $(docker inspect -f '{{.State.Status}}' $c 2>/dev/null)"
done

echo
echo "=== 5. 健康检查 ==="
for pair in "single|http://l9-vm-single:8428" "vmselect|http://l9-vmselect:8481"; do
  n=${pair%%|*}; u=${pair#*|}
  code=$(docker run --rm --network $NET curlimages/curl:latest -s -o /dev/null -w '%{http_code}' "$u/health" 2>/dev/null || echo 000)
  echo "  $n /health -> $code"
done
