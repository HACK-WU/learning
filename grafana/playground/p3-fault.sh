#!/bin/bash
set -u
W=/mnt/d/projects/learning/grafana/projects/从告警到定位

echo "=== 1. 注入故障：重启应用并开启 FAULT_MODE ==="
docker rm -f p3-shop >/dev/null 2>&1
docker run -d --name p3-shop --network grafana-net \
  -p 9400:9400 -p 9401:9401 \
  -e SERVICE_NAME=shop-api \
  -e OTLP_ENDPOINT=http://grafana-jaeger:4318/v1/traces \
  -e LOKI_URL=http://grafana-loki:3100/loki/api/v1/push \
  -e FAULT_MODE=1 \
  -v "$W/实现/app/logs:/var/log/shop" \
  p3-shop:1.0 2>&1 | tail -1
sleep 12
docker logs p3-shop 2>&1 | grep '故障注入' | head -2
echo

echo "=== 2. 等 70 秒让故障数据积累 ==="
sleep 70
echo "  done"
echo

echo "=== 3. checkout 的 P90 延迟（应该飙高）==="
curl -s --noproxy '*' -m 8 -G http://localhost:3110/api/v1/query --data-urlencode 'query=histogram_quantile(0.9, sum by (le, route) (rate(shop_request_duration_seconds_bucket[2m])))' 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']['result']
for r in sorted(d, key=lambda x: -float(x['value'][1])):
    print('   ', r['metric'].get('route'), 'P90=', round(float(r['value'][1]),3), 's')
" 2>&1
echo

echo "=== 4. 错误率（checkout 应该有 5xx）==="
curl -s --noproxy '*' -m 8 -G http://localhost:3110/api/v1/query --data-urlencode 'query=sum by (route) (rate(shop_requests_total{status="500"}[2m]))' 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']['result']
if not d: print('    (无 500 错误)')
for r in d: print('   ', r['metric'].get('route'), '错误率=', round(float(r['value'][1]),4))
" 2>&1
echo

echo "=== 5. Loki 里的 ERROR 日志（应该能看到 DownstreamTimeout）==="
curl -s --noproxy '*' -m 10 -G 'http://localhost:3101/loki/api/v1/query_range' --data-urlencode 'query={job="shop"} |= "ERROR"' --data-urlencode 'limit=3' --data-urlencode "start=$(( $(date +%s) - 300 ))000000000" --data-urlencode "end=$(date +%s)000000000" 2>&1 | head -c 800
echo
echo

echo "=== 6. Jaeger 里有 error 的 trace 吗 ==="
curl -s --noproxy '*' -m 10 -G 'http://localhost:16687/api/traces' --data-urlencode 'service=shop-api' --data-urlencode 'limit=5' 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin).get('data',[])
print('   返回 trace 数:', len(d))
for t in d[:3]:
    errs=[s for s in t['spans'] if any(x.get('key')=='error' for x in s.get('tags',[]))]
    print('   ', t['traceID'][:16], 'spans=', len(t['spans']), '错误span=', len(errs))
" 2>&1
