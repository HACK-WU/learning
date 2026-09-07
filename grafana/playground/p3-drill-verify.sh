#!/bin/bash
set -u
G=http://localhost:3130
P=http://localhost:3110

echo "########## 验证三级下钻 ##########"
echo

echo "=== 1. 指标 → 链路：exemplar 圆点存在吗 ==="
echo "  查 Prometheus 的 exemplar（需要 histogram 观测时带 trace_id）"
curl -s --noproxy '*' -m 10 -G "$P/api/v1/query_exemplars" --data-urlencode 'query=shop_request_duration_seconds_bucket' 2>&1 | head -c 500
echo
echo

echo "=== 2. 应用有没有把 trace_id 挂到 exemplar 上 ==="
echo "  prometheus_client 的 Histogram 默认【不会】自动挂 exemplar，"
echo "  需要显式传 exemplar={'trace_id': ...}。检查应用代码与 /metrics 输出："
curl -s --noproxy '*' -m 8 http://localhost:9400/metrics 2>&1 | grep -E 'shop_request_duration_seconds_bucket\{le="0.1"' | head -3
echo "  --- 看有没有 # HELP 后的 trace_id 字样 ---"
curl -s --noproxy '*' -m 8 http://localhost:9400/metrics 2>&1 | grep -i 'trace' | head -5
echo

echo "=== 3. 日志 → 链路：Loki 里能搜到 trace_id 吗 ==="
TID=$(docker logs p3-shop 2>&1 | grep -o '"trace_id": "[a-f0-9]\{32\}"' | head -1 | grep -o '[a-f0-9]\{32\}')
echo "  取一条 trace_id = $TID"
if [ -n "$TID" ]; then
  curl -s --noproxy '*' -m 10 -G 'http://localhost:3101/loki/api/v1/query_range' --data-urlencode "query={job=\"shop\"} |= \"$TID\"" --data-urlencode 'limit=5' --data-urlencode "start=$(( $(date +%s) - 900 ))000000000" --data-urlencode "end=$(date +%s)000000000" 2>&1 | head -c 400
  echo
  echo "  --- 这个 trace 在 Jaeger 里吗 ---"
  curl -s --noproxy '*' -m 10 "http://localhost:16687/api/traces/$TID" 2>&1 | head -c 300
  echo
fi
echo

echo "=== 4. 通过 Grafana 数据源代理验证下钻链路（真实前端路径）==="
echo "  --- Grafana 查 Loki ---"
curl -s --noproxy '*' -u admin:admin -m 15 -X POST "$G/api/ds/query" -H 'Content-Type: application/json' -d '{"queries":[{"refId":"A","datasource":{"uid":"shop-loki"},"expr":"{job=\"shop\"} | json | level=\"ERROR\"","queryType":"range"}],"from":"now-15m","to":"now"}' 2>&1 | head -c 500
echo
echo

echo "=== 5. Grafana 查 Jaeger（链路）==="
curl -s --noproxy '*' -u admin:admin -m 15 -X POST "$G/api/ds/query" -H 'Content-Type: application/json' -d '{"queries":[{"refId":"A","datasource":{"uid":"shop-jaeger"},"query":"shop-api","queryType":"traces"}],"from":"now-15m","to":"now"}' 2>&1 | head -c 400
echo
