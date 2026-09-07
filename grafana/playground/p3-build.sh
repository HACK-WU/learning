#!/bin/bash
set -u
W=/mnt/d/projects/learning/grafana/projects/从告警到定位
cd "$W/实现/app" || exit 1

echo "=== 1. 构建应用镜像 ==="
docker build -t p3-shop:1.0 . 2>&1 | tail -8
echo

echo "=== 2. 确认镜像 ==="
docker images p3-shop --format '  {{.Repository}}:{{.Tag}}  {{.Size}}'
echo

echo "=== 3. 启动应用（接入 grafana-net，让 Prometheus 能抓到）==="
docker rm -f p3-shop >/dev/null 2>&1
docker run -d --name p3-shop --network grafana-net \
  -p 9400:9400 -p 9401:9401 \
  -e SERVICE_NAME=shop-api \
  -e OTLP_ENDPOINT=http://grafana-jaeger:4318/v1/traces \
  -e FAULT_MODE=0 \
  -v "$W/实现/app/logs:/var/log/shop" \
  p3-shop:1.0 2>&1 | tail -2
sleep 12
echo "  状态: $(docker ps -a --filter name=p3-shop --format '{{.Status}}')"
echo

echo "=== 4. 应用日志前 10 行（看 trace_id 是否写进去了）==="
docker logs p3-shop 2>&1 | head -10
echo

echo "=== 5. 指标端点 ==="
curl -s --noproxy '*' -m 8 http://localhost:9400/metrics 2>&1 | grep -E '^shop_' | head -20
echo

echo "=== 6. 健康检查 ==="
curl -s --noproxy '*' -m 5 http://localhost:9401/health 2>&1
echo
echo

echo "=== 7. 日志文件是否落盘（供 Promtail 采集）==="
ls -la "$W/实现/app/logs/" 2>&1 | head -5
wc -l "$W/实现/app/logs/app.log" 2>&1
