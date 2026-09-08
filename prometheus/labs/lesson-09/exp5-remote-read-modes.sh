#!/usr/bin/env bash
# 回收课 7 挂账项：remote read 三种模式的分模式性能差异
# 课 7 只测了整体代价 2.69x，本课拆解到每种模式
#
# 三种读取模式：
#   1. 全量拉取（默认，客户端无流式能力）：一次性把所有样本拉回，内存峰值高
#   2. 流式 chunk（3.x，StreamedChunkedReadResponses）：边读边处理
#   3. 原生 protobuf 协议（ negotiated 编码）
#
# 实测手法：对同一组 query、同一时间范围，分别统计
#   耗时 / 返回字节数 / 响应分块数
set -uo pipefail
NET=l9net

# 准备一个有 remote read 的 Prometheus：读 VM 单节点
echo "=== 1. 准备带 remote_read 的 Prometheus ==="
cat > /tmp/prom-rr.yml <<'EOF'
global:
  scrape_interval: 5s
remote_read:
  - url: http://l9-vm-single:8428/prometheus/api/v1/read
    read_recent: true
    name: vm_single
EOF
docker rm -f l9-prom-rr 2>/dev/null || true
docker run -d --name l9-prom-rr --network $NET \
  -v /tmp/prom-rr.yml:/etc/prometheus/prometheus.yml:ro \
  -v /tmp:/hosttmp \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=2h >/dev/null
echo "l9-prom-rr started"

# 先让 VM 有数据：起一个 Prometheus 写进去
cat > /tmp/prom-wr.yml <<'EOF'
global:
  scrape_interval: 5s
scrape_configs:
  - job_name: app
    static_configs:
      - targets: ["l9-app:8000"]
remote_write:
  - url: http://l9-vm-single:8428/api/v1/write
EOF
docker rm -f l9-prom-wr 2>/dev/null || true
docker run -d --name l9-prom-wr --network $NET \
  -v /tmp/prom-wr.yml:/etc/prometheus/prometheus.yml:ro \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=2h >/dev/null
echo "l9-prom-wr started（向 VM 写入数据）"

echo "等待数据采集与写入（30s）..."
sleep 30

echo
echo "=== 2. 确认 VM 里已有数据 ==="
docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode 'query=count(app_requests_total)' \
  http://l9-vm-single:8428/prometheus/api/v1/query 2>/dev/null | head -c 200
echo
