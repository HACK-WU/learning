#!/usr/bin/env bash
# VM 课 0 环境探针：确认单节点 VictoriaMetrics 的核心 API 在本机 WSL Docker 上全部可用
set -u
DOCKER_NAME="${DOCKER_NAME:-vm-learn}"
PORT="${PORT:-8428}"
BASE="http://localhost:${PORT}"

echo "=== 0. 容器状态 ==="
docker inspect -f 'state={{.State.Status}} image={{.Config.Image}}' "$DOCKER_NAME" 2>&1

echo
echo "=== 1. 版本号（二进制自报）==="
docker exec "$DOCKER_NAME" /victoria-metrics-prod --version 2>&1 | head -2

echo
echo "=== 2. /health ==="
curl -s -m 10 "$BASE/health"
echo

echo
echo "=== 3. 写入（/api/v1/import/prometheus，带显式时间戳）==="
NOW=$(date +%s)
echo "NOW=$NOW"
curl -s -m 10 -w "http=%{http_code}\n" -X POST "$BASE/api/v1/import/prometheus" \
  --data-binary "up{job=\"test\",instance=\"localhost:8428\"} 1 ${NOW}000"
curl -s -m 10 -w "http=%{http_code}\n" -X POST "$BASE/api/v1/import/prometheus" \
  --data-binary "demo_metric{env=\"dev\"} 42 ${NOW}000"

echo
echo "=== 4. 回查 /api/v1/query?query=up ==="
curl -s -m 10 --data-urlencode "query=up" "$BASE/api/v1/query"
echo

echo
echo "=== 5. 序列总数 /api/v1/series/count ==="
curl -s -m 10 "$BASE/api/v1/series/count"
echo

echo
echo "=== 6. 标签列表 /api/v1/labels ==="
curl -s -m 10 "$BASE/api/v1/labels"
echo

echo
echo "=== 7. Prometheus remote write 端点 /prometheus/api/v1/write ==="
curl -s -m 10 -w "http=%{http_code}\n" -X POST "$BASE/prometheus/api/v1/write" \
  --data-binary "demo_metric{env=\"prod\"} 7 ${NOW}000"

echo
echo "=== 8. InfluxDB line protocol 端点 /write ==="
curl -s -m 10 -w "http=%{http_code}\n" -X POST "$BASE/write" \
  --data-binary "influx_demo,host=h1 value=3.5 ${NOW}000000000"

echo
echo "=== 9. 再次统计序列数（应 >= 3）==="
curl -s -m 10 "$BASE/api/v1/series/count"
echo

echo
echo "=== 10. vmui 页面可达性 ==="
curl -s -o /dev/null -w "vmui_http=%{http_code}\n" -m 10 "$BASE/vmui/"

echo
echo "=== 11. 自监控指标条数 /metrics 中 vm_ 前缀 ==="
curl -s -m 10 "$BASE/metrics" | grep -c '^vm_'
