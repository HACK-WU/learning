#!/usr/bin/env bash
set -uo pipefail
NET=l9net

echo "=== 1. 直连两个 Prometheus 看数据是否存在 ==="
for i in 1 2; do
  echo "-- l9-prom-$i --"
  docker run --rm --network $NET curlimages/curl:latest -s -G \
    --data-urlencode 'query=app_requests_total' \
    "http://l9-prom-$i:9090/api/v1/query" 2>/dev/null \
    | head -c 300
  echo
done

echo
echo "=== 2. Thanos querier 查 up 指标（最基础，必存在）==="
docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode 'query=up' \
  "http://l9-thanos-query:19191/api/v1/query" 2>/dev/null | head -c 400
echo

echo
echo "=== 3. Thanos querier 的所有 __name__ ==="
docker run --rm --network $NET curlimages/curl:latest -s \
  "http://l9-thanos-query:19191/api/v1/label/__name__/values" 2>/dev/null | head -c 600
echo

echo
echo "=== 4. querier 最近日志（有无查询错误）==="
docker logs l9-thanos-query 2>&1 | tail -8
