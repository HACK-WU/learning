#!/bin/bash
echo "=== 1. 直接看应用暴露了哪些指标 ==="
curl -s --noproxy '*' -m 8 http://localhost:9400/metrics 2>&1 | grep -c '^shop_' | xargs echo "  shop_ 指标行数:"
curl -s --noproxy '*' -m 8 http://localhost:9400/metrics 2>&1 | grep '^shop_requests_total{' | head -5
echo

echo "=== 2. Prometheus 里 shop_ 开头的指标有哪些 ==="
curl -s --noproxy '*' -m 8 -G http://localhost:3110/api/v1/label/__name__/values 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin).get('data',[])
shop=[x for x in d if x.startswith('shop_')]
print('  shop_ 指标数:', len(shop))
for x in shop[:12]: print('   ', x)
" 2>&1
echo

echo "=== 3. 用 instant 查原始值（不用 rate）==="
curl -s --noproxy '*' -m 8 -G http://localhost:3110/api/v1/query --data-urlencode 'query=shop_requests_total' 2>&1 | head -c 400
echo
echo

echo "=== 4. 用 5m 窗口的 rate ==="
curl -s --noproxy '*' -m 8 -G http://localhost:3110/api/v1/query --data-urlencode 'query=sum(rate(shop_requests_total[5m])) by (route)' 2>&1 | head -c 400
echo
echo

echo "=== 5. 等 40 秒积累数据后再查 1m rate ==="
sleep 40
curl -s --noproxy '*' -m 8 -G http://localhost:3110/api/v1/query --data-urlencode 'query=sum(rate(shop_requests_total[1m])) by (route)' 2>&1 | head -c 600
echo
echo

echo "=== 6. P90 延迟（5m 窗口）==="
curl -s --noproxy '*' -m 8 -G http://localhost:3110/api/v1/query --data-urlencode 'query=histogram_quantile(0.9, sum by (le, route) (rate(shop_request_duration_seconds_bucket[5m])))' 2>&1 | head -c 600
echo
