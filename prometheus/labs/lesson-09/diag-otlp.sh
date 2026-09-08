#!/usr/bin/env bash
set -uo pipefail
NET=l9net

echo "=== 1. features 完整输出（otlp_receiver 分类）==="
docker run --rm --network $NET curlimages/curl:latest -s \
  http://l9-prom-otlp:9090/api/v1/features 2>/dev/null \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']
for k,v in d.items():
    if 'otlp' in k or 'otlp' in str(v):
        print('   %s: %s' % (k,v))
"

echo
echo "=== 2. 直接 POST 一个最小 OTLP JSON 到端点，看返回码 ==="
# OTLP/HTTP JSON 格式，一个最简单的 gauge
cat > /tmp/otlp-payload.json <<'EOF'
{
  "resourceMetrics": [{
    "resource": {
      "attributes": [{"key":"service.name","value":{"stringValue":"otlp-test"}}]
    },
    "scopeMetrics": [{
      "scope": {"name":"test"},
      "metrics": [{
        "name": "test.metric.total",
        "unit": "1",
        "gauge": {
          "dataPoints": [{
            "asDouble": 42,
            "timeUnixNano": "1788749000000000000",
            "attributes": [{"key":"route","value":{"stringValue":"/"}}]
          }]
        }
      }]
    }]
  }]
}
EOF
echo -n "   POST /api/v1/otlp/v1/metrics -> "
docker run --rm --network $NET \
  -v /tmp/otlp-payload.json:/p.json:ro \
  curlimages/curl:latest -s -o /dev/null -w '%{http_code}\n' \
  -X POST http://l9-prom-otlp:9090/api/v1/otlp/v1/metrics \
  -H 'Content-Type: application/json' \
  --data-binary @/p.json 2>/dev/null

echo
echo "=== 3. 端点路径确认（/api/v1/otlp vs /api/v1/otlp/v1/metrics）==="
for p in /api/v1/otlp /api/v1/otlp/v1/metrics; do
  printf '   %-28s -> ' "$p"
  docker run --rm --network $NET \
    -v /tmp/otlp-payload.json:/p.json:ro \
    curlimages/curl:latest -s -o /dev/null -w '%{http_code}\n' \
    -X POST "http://l9-prom-otlp:9090$p" \
    -H 'Content-Type: application/json' \
    --data-binary @/p.json 2>/dev/null
done

echo
echo "=== 4. 再次查 __name__（等 10s 让数据落定）==="
sleep 10
docker run --rm --network $NET curlimages/curl:latest -s \
  http://l9-prom-otlp:9090/api/v1/label/__name__/values 2>/dev/null | head -c 400
echo

echo
echo "=== 5. Prom 日志里 otlp 相关 ==="
docker logs l9-prom-otlp 2>&1 | grep -i otlp | tail -5 || echo "  (无)"
