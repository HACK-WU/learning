#!/bin/bash
set -u
W=/mnt/d/projects/learning/grafana/projects/从告警到定位
cd "$W/实现/app" || exit 1

echo "=== 1. 重建镜像 ==="
docker build -t p3-shop:1.0 . 2>&1 | tail -3
echo

echo "=== 2. 重启应用（带 LOKI_URL）==="
docker rm -f p3-shop >/dev/null 2>&1
docker run -d --name p3-shop --network grafana-net \
  -p 9400:9400 -p 9401:9401 \
  -e SERVICE_NAME=shop-api \
  -e OTLP_ENDPOINT=http://grafana-jaeger:4318/v1/traces \
  -e LOKI_URL=http://grafana-loki:3100/loki/api/v1/push \
  -e FAULT_MODE=0 \
  -v "$W/实现/app/logs:/var/log/shop" \
  p3-shop:1.0 2>&1 | tail -1
sleep 15
echo "  状态: $(docker ps -a --filter name=p3-shop --format '{{.Status}}')"
echo

echo "=== 3. 应用日志（看有没有 loki push failed）==="
docker logs p3-shop 2>&1 | grep -iE 'loki|启动' | head -5
echo

echo "=== 4. 查 Loki 有没有 shop 日志 ==="
curl -s --noproxy '*' -m 10 -G 'http://localhost:3101/loki/api/v1/query_range' --data-urlencode 'query={job="shop"}' --data-urlencode 'limit=3' --data-urlencode "start=$(( $(date +%s) - 600 ))000000000" --data-urlencode "end=$(date +%s)000000000" 2>&1 | head -c 900
echo
echo

echo "=== 5. Loki 的 label 列表 ==="
curl -s --noproxy '*' -m 10 http://localhost:3101/loki/api/v1/labels 2>&1 | head -c 300
echo
echo

echo "=== 6. 确认 trace 进了 Jaeger ==="
curl -s --noproxy '*' -m 10 http://localhost:16687/api/services 2>&1 | head -c 200
echo
echo

echo "=== 7. Prometheus 抓到 shop 指标了吗 ==="
curl -s --noproxy '*' -m 8 http://localhost:9201/api/v1/query --data-urlencode 'query=up{job="shop"}' 2>&1 | head -c 300
echo
