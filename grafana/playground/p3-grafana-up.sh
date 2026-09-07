#!/bin/bash
set -u
W=/mnt/d/projects/learning/grafana/projects/从告警到定位

echo "=== 1. 生成 dashboard JSON ==="
cd "$W/实现" && python3 gen_dashboard.py 2>&1 || uv run python gen_dashboard.py 2>&1
echo

echo "=== 2. 校验 JSON 合法 ==="
python3 -c "
import json
d=json.load(open('$W/dashboards/shop-overview.json'))
print('  uid =', d['uid'])
print('  面板数 =', len(d['panels']))
for p in d['panels']: print('   ', p['id'], p['type'], p['title'][:32])
" 2>&1
echo

echo "=== 3. 起项目专属 Grafana（3130），全部走 provisioning ==="
docker rm -f p3-grafana >/dev/null 2>&1
docker run -d --name p3-grafana --network grafana-net -p 3130:3000 \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  -e GF_USERS_ALLOW_SIGN_UP=false \
  -e GF_FEATURE_TOGGLES_ENABLE=traceToMetrics \
  -v "$W/实现/provisioning:/etc/grafana/provisioning:ro" \
  -v "$W/dashboards:/var/lib/grafana/dashboards:ro" \
  grafana/grafana:13.2.1 2>&1 | tail -1
for i in $(seq 1 45); do
  R=$(curl -s --noproxy '*' -m 3 http://localhost:3130/api/health | tr -d ' \n')
  if [ -n "$R" ]; then echo "  ${i}x2s: $R"; break; fi
  sleep 2
done
echo

echo "=== 4. 数据源是否被 provisioning 建出来 ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3130/api/datasources 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)
for x in d: print('   ', x['uid'], x['type'], x.get('url',''), 'default' if x.get('isDefault') else '')
" 2>&1
echo

echo "=== 5. dashboard 是否被加载 ==="
curl -s --noproxy '*' -u admin:admin 'http://localhost:3130/api/search?limit=50' 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  dashboard 数 =', len(d))
for x in d: print('   ', x['uid'], x['title'])
" 2>&1
echo

echo "=== 6. provisioning 日志有没有报错 ==="
docker logs p3-grafana 2>&1 | grep -iE 'error|fail|provision' | head -10
