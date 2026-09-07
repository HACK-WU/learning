#!/bin/bash
set -u
W=/mnt/d/projects/learning/grafana/projects/从告警到定位

echo "=== 1. 起项目专属 Prometheus（3110）==="
docker rm -f p3-prom >/dev/null 2>&1
docker run -d --name p3-prom --network grafana-net -p 3110:9090 \
  -v "$W/实现/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --enable-feature=exemplar-storage 2>&1 | tail -1
sleep 12
echo "  状态: $(docker ps -a --filter name=p3-prom --format '{{.Status}}')"
echo

echo "=== 2. 健康 ==="
curl -s --noproxy '*' -m 8 http://localhost:3110/-/healthy 2>&1
echo

echo "=== 3. target 状态 ==="
curl -s --noproxy '*' -m 8 http://localhost:3110/api/v1/targets 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']['activeTargets']
for t in d: print('   ', t['labels'].get('job'), t['scrapeUrl'], t['health'], t.get('lastError','')[:60])
" 2>&1
echo

echo "=== 4. shop 指标查得到吗 ==="
curl -s --noproxy '*' -m 8 http://localhost:3110/api/v1/query --data-urlencode 'query=up{job="shop"}' 2>&1 | head -c 300
echo
echo

echo "=== 5. 请求速率（项目核心指标）==="
curl -s --noproxy '*' -m 8 -G http://localhost:3110/api/v1/query --data-urlencode 'query=sum(rate(shop_requests_total[1m])) by (route)' 2>&1 | head -c 500
echo
echo

echo "=== 6. P90 延迟（告警要盯的指标）==="
curl -s --noproxy '*' -m 8 -G http://localhost:3110/api/v1/query --data-urlencode 'query=histogram_quantile(0.9, sum(rate(shop_request_duration_seconds_bucket[1m])) by (le, route))' 2>&1 | head -c 500
echo
