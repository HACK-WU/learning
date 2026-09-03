#!/usr/bin/env bash
# VM 课 0 调试：为什么 /api/v1/import/prometheus 返回 204 却查不到数据
set -u
DOCKER_NAME="${DOCKER_NAME:-vm-learn}"
BASE="http://localhost:8428"

echo "=== A. 容器启动参数与数据目录 ==="
docker inspect -f '{{range .Args}}{{.}} {{end}}' "$DOCKER_NAME"
echo
docker exec "$DOCKER_NAME" ls -la /victoria-metrics-data 2>&1 | head -20

echo
echo "=== B. 容器内时间 vs 宿主机时间 ==="
echo -n "container: "; docker exec "$DOCKER_NAME" date +%s
echo -n "wsl host : "; date +%s

echo
echo "=== C. 写入一条，立刻用显式时间范围查 ==="
NOW=$(date +%s)
echo "write_ts_sec=${NOW}"
curl -s -m 10 -w "import_http=%{http_code}\n" -X POST "$BASE/api/v1/import/prometheus" \
  --data-binary "probe_metric{job=\"probe\"} 1 ${NOW}000"

sleep 2

START=$((NOW - 600))
END=$((NOW + 600))
echo "-- range 查询 probe_metric（窗口 ±600s）--"
curl -s -m 10 --data-urlencode "query=probe_metric" \
  --data-urlencode "start=${START}" --data-urlencode "end=${END}" \
  --data-urlencode "step=60" "$BASE/api/v1/query_range"
echo

echo
echo "-- 瞬时查询，带显式 time 参数 --"
curl -s -m 10 --data-urlencode "query=probe_metric" \
  --data-urlencode "time=${NOW}" "$BASE/api/v1/query"
echo

echo
echo "=== D. /api/v1/series 列出序列 ==="
curl -s -m 10 --data-urlencode 'match[]={__name__=~".*"}' "$BASE/api/v1/series" | head -c 800
echo

echo
echo "=== E. 容器日志尾部（看是否有写入报错）==="
docker logs --tail 25 "$DOCKER_NAME" 2>&1

echo
echo "=== F. 自监控：写入相关指标 ==="
curl -s -m 10 "$BASE/metrics" | grep -E '^vm_(insert|http_requests_total|rows)' | head -20
