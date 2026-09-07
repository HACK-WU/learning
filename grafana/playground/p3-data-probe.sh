#!/bin/bash
echo "=== 1. Loki (3101) 有数据吗 ==="
echo "  --- ready ---"
curl -s --noproxy '*' -m 8 http://localhost:3101/ready 2>&1 | head -c 120
echo
echo "  --- label 有哪些 ---"
curl -s --noproxy '*' -m 8 http://localhost:3101/loki/api/v1/labels 2>&1 | head -c 400
echo
echo "  --- 查最近日志（limit 3）---"
curl -s --noproxy '*' -m 10 -G 'http://localhost:3101/loki/api/v1/query_range' --data-urlencode 'query={job=~".+"}' --data-urlencode 'limit=3' --data-urlencode "start=$(( $(date +%s) - 3600 ))000000000" --data-urlencode "end=$(date +%s)000000000" 2>&1 | head -c 600
echo
echo

echo "=== 2. Grafana 里 Loki 数据源是否已配 ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3001/api/datasources 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)
for x in d: print('   ', x['uid'], x['type'], x.get('url',''), 'isDefault' if x.get('isDefault') else '')
" 2>&1
echo

echo "=== 3. Jaeger (16687) 有 trace 吗 ==="
echo "  --- services ---"
curl -s --noproxy '*' -m 8 http://localhost:16687/api/services 2>&1 | head -c 300
echo
echo "  --- 查一个 service 的 trace ---"
SVC=$(curl -s --noproxy '*' -m 8 http://localhost:16687/api/services 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin).get('data',[]);print(d[0] if d else '')" 2>/dev/null)
echo "  svc=$SVC"
if [ -n "$SVC" ]; then
  curl -s --noproxy '*' -m 10 -G "http://localhost:16687/api/traces" --data-urlencode "service=$SVC" --data-urlencode 'limit=2' 2>&1 | head -c 400
fi
echo
echo

echo "=== 4. exemplar 数据（prom-ex 9202）==="
curl -s --noproxy '*' -m 8 http://localhost:9202/api/v1/query --data-urlencode 'query=up' 2>&1 | head -c 300
echo
echo "  --- 有 exemplar 的指标（histogram）---"
curl -s --noproxy '*' -m 8 -G 'http://localhost:9202/api/v1/query_range' --data-urlencode 'query=histogram_quantile(0.9, sum(rate(test_histogram_bucket[5m])) by (le))' --data-urlencode "start=$(( $(date +%s) - 1800 ))" --data-urlencode "end=$(date +%s)" --data-urlencode 'step=60s' 2>&1 | head -c 500
echo
echo

echo "=== 5. grafana-prom(9201) 有哪些可用指标（前 20）==="
curl -s --noproxy '*' -m 8 http://localhost:9201/api/v1/label/__name__/values 2>&1 | python3 -c "import sys,json;d=json.load(sys.stdin).get('data',[]);print(len(d));[print('   ',x) for x in d[:20]]" 2>&1
echo

echo "=== 6. node-exporter 指标（9101）==="
curl -s --noproxy '*' -m 8 http://localhost:9101/metrics 2>&1 | grep -c '^node_' | xargs echo "  node_ 指标数:"
echo

echo "=== 7. Grafana 现有 dashboard 清单（3001）==="
curl -s --noproxy '*' -u admin:admin 'http://localhost:3001/api/search?limit=100' 2>&1 | python3 -c "import sys,json;d=json.load(sys.stdin);print('  共',len(d));[print('   ',x['uid'],x['title']) for x in d[:15]]" 2>&1
