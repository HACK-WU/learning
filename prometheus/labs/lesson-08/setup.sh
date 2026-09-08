#!/usr/bin/env bash
# 课 8《联邦与全局视图》主环境
# 端口段：19110~19119（课 7 占用 19099~19107）
#
# 拓扑：
#   l8-app          数据源（507 条序列）
#   l8-leaf-a       叶子 Prometheus（抓 app，external_labels: cluster=leaf-a）
#   l8-leaf-b       叶子 Prometheus（抓 app，external_labels: cluster=leaf-b）
#   l8-replica-1    HA 副本 1（抓 app，external_labels: cluster=ha, replica=1）
#   l8-replica-2    HA 副本 2（抓 app，external_labels: cluster=ha, replica=2）
#   l8-global       全局 Prometheus（联邦抓取 leaf-a / leaf-b）
#   l8-vm           VictoriaMetrics（作为"后端去重"的对照：接收双写）
set -e
L8=/mnt/d/projects/learning/prometheus/labs/lesson-08
cd "$L8"

echo "=== 0. 清理旧容器 ==="
docker rm -f l8-app l8-leaf-a l8-leaf-b l8-replica-1 l8-replica-2 \
             l8-global l8-vm l8-am-1 l8-am-2 >/dev/null 2>&1 || true
docker network rm l8net >/dev/null 2>&1 || true
docker network create l8net >/dev/null

echo "=== 1. 构建数据源镜像 ==="
docker build -q -t l8-app:latest ./app

echo "=== 2. 启动数据源 ==="
docker run -d --name l8-app --network l8net l8-app:latest >/dev/null

echo "=== 3. 启动两个叶子 Prometheus（分层联邦的下层） ==="
docker run -d --name l8-leaf-a --network l8net -p 19110:9090 \
  -v "$L8/leaf-a.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus --storage.tsdb.retention.time=2h \
  --web.enable-lifecycle >/dev/null

docker run -d --name l8-leaf-b --network l8net -p 19111:9090 \
  -v "$L8/leaf-b.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus --storage.tsdb.retention.time=2h \
  --web.enable-lifecycle >/dev/null

echo "=== 4. 启动 HA 双副本（抓同一 target，external_labels 带 replica） ==="
docker run -d --name l8-replica-1 --network l8net -p 19112:9090 \
  -v "$L8/replica-1.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus --storage.tsdb.retention.time=2h \
  --web.enable-lifecycle >/dev/null

docker run -d --name l8-replica-2 --network l8net -p 19113:9090 \
  -v "$L8/replica-2.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus --storage.tsdb.retention.time=2h \
  --web.enable-lifecycle >/dev/null

echo "=== 5. 启动全局 Prometheus（联邦抓取两个叶子） ==="
docker run -d --name l8-global --network l8net -p 19114:9090 \
  -v "$L8/global.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus --storage.tsdb.retention.time=2h \
  --web.enable-lifecycle >/dev/null

echo "=== 6. 启动 VictoriaMetrics（接收 HA 双写，用于验证后端去重） ==="
docker run -d --name l8-vm --network l8net -p 19115:8428 \
  victoriametrics/victoria-metrics:v1.151.0 \
  -storageDataPath=/vmdata -retentionPeriod=1 \
  -dedup.minScrapeInterval=1s >/dev/null

echo
echo "=== 等待就绪 ==="
sleep 12
for c in l8-app l8-leaf-a l8-leaf-b l8-replica-1 l8-replica-2 l8-global l8-vm; do
  s=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "MISSING")
  printf "  %-14s %s\n" "$c" "$s"
done

echo
echo "=== 端口映射 ==="
echo "  l8-leaf-a    19110"
echo "  l8-leaf-b    19111"
echo "  l8-replica-1 19112"
echo "  l8-replica-2 19113"
echo "  l8-global    19114"
echo "  l8-vm        19115"
