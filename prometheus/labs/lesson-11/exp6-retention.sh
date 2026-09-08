#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-11
NET=l11cnet; PORT=19456

docker rm -f l11c-ret >/dev/null 2>&1 || true
mkdir -p $D/conf-ret
cat > $D/conf-ret/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s
scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
EOF
docker run -d --name l11c-ret --network $NET -p $PORT:9090 \
  -v $D/conf-ret:/etc/prometheus \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=15d \
  --web.enable-lifecycle --web.enable-admin-api >/dev/null
for i in $(seq 1 60); do curl -sf "http://localhost:$PORT/-/ready" >/dev/null 2>&1 && break; sleep 1; done
sleep 20

echo "=== 实验：retention 能否热更新 ==="
echo ""
echo "--- 启动参数: --storage.tsdb.retention.time=15d ---"
docker logs l11c-ret 2>&1 | grep -i "retention" | head -3
echo ""
echo "--- 修改配置文件，加入 tsdb.retention: 1h ---"
cat > $D/conf-ret/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s
tsdb:
  retention: 1h
scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
EOF
echo "已更新配置（新增 tsdb.retention: 1h）"
echo "--- 发送 SIGHUP 热加载 ---"
docker exec l11c-ret kill -HUP 1
sleep 8
echo ""
echo "--- 热加载后的日志 ---"
docker logs l11c-ret 2>&1 | grep -iE "retention|Loading configuration" | tail -5
echo ""
echo "=== 结论 ==="
docker logs l11c-ret 2>&1 | grep -i "retention updated" | tail -2 || echo "  未见 retention updated 日志"
