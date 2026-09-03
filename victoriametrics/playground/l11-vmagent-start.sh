#!/bin/bash
set -u
NET=vm-cluster-net
P=/mnt/d/projects/learning/victoriametrics/playground
mkdir -p $P/vmagent-data $P/vmalert-data $P/alertmanager-data

echo "=== 1. 准备 vmagent 抓取配置 ==="
cat > $P/prometheus-vmagent.yml <<'EOF'
global:
  scrape_interval: 5s

scrape_configs:
  - job_name: 'vmagent-self'
    static_configs:
      - targets: ['localhost:8429']
  - job_name: 'vmsingle'
    static_configs:
      - targets: ['vm-learn:8428']
    metrics_path: '/metrics'
EOF
echo "配置文件已写入"

echo
echo "=== 2. 启动 vmagent（持久化队列 200MB）==="
docker rm -f vmagent-learn >/dev/null 2>&1
docker run -d --name vmagent-learn --network $NET \
  -p 8429:8429 \
  -v $P/prometheus-vmagent.yml:/etc/prometheus/prometheus.yml:ro \
  -v $P/vmagent-data:/vmagent-remotewrite-data \
  victoriametrics/vmagent:v1.151.0 \
  -promscrape.config=/etc/prometheus/prometheus.yml \
  -remoteWrite.url=http://vminsert-learn:8480/insert/0/prometheus/api/v1/write \
  -remoteWrite.maxDiskUsagePerURL=209715200 \
  -remoteWrite.tmpDataPath=/vmagent-remotewrite-data \
  -httpListenAddr=:8429 \
  -loggerLevel=INFO
echo "启动命令已发出，等待 15 秒..."
sleep 15

echo
echo "=== 3. 容器状态 ==="
docker ps --filter name=vmagent-learn --format '{{.Names}} | {{.Status}}'

echo
echo "=== 4. vmagent /healthz ==="
curl -s -o /dev/null -w "  HTTP %{http_code}\n" http://localhost:8429/healthz

echo
echo "=== 5. vmagent 的 targets（抓取目标状态）==="
curl -s http://localhost:8429/api/v1/targets 2>/dev/null | head -c 600
echo

echo
echo "=== 6. 持久化队列目录 ==="
docker exec vmagent-learn ls -la /vmagent-remotewrite-data/ 2>&1 | head -20
