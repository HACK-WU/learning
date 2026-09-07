#!/bin/bash
set -u
W=/mnt/d/projects/learning/grafana/projects/从告警到定位

echo "=== 1. 重启 Grafana 加载告警 provisioning ==="
docker restart p3-grafana >/dev/null 2>&1
for i in $(seq 1 45); do
  R=$(curl -s --noproxy '*' -m 3 http://localhost:3130/api/health | tr -d ' \n')
  if [ -n "$R" ]; then echo "  ${i}x2s: $R"; break; fi
  sleep 2
done
echo

echo "=== 2. 告警规则是否被建出来 ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3130/api/v1/provisioning/alert-rules 2>&1 | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    if isinstance(d,list):
        print('  规则数 =', len(d))
        for r in d: print('   ', r.get('uid'), '|', r.get('title'), '| for=', r.get('for'))
    else: print('  返回:', str(d)[:300])
except Exception as e: print('  解析失败:', e)
" 2>&1
echo

echo "=== 3. 联系人与通知策略 ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3130/api/v1/provisioning/contact-points 2>&1 | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    for c in d: print('   ', c.get('name'), '->', [r.get('type') for r in c.get('receivers',[])])
except Exception as e: print('  ', e)
" 2>&1
echo
curl -s --noproxy '*' -u admin:admin http://localhost:3130/api/v1/provisioning/policies 2>&1 | head -c 400
echo
echo

echo "=== 4. provisioning 告警日志 ==="
docker logs p3-grafana 2>&1 | grep -iE 'alert.*provision|provisioning.*alert|error' | tail -8
echo

echo "=== 5. 当前告警实例状态 ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3130/api/alertmanager/grafana/api/v2/alerts 2>&1 | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print('  活跃告警数 =', len(d) if isinstance(d,list) else '?')
    for a in (d if isinstance(d,list) else [])[:5]:
        print('   ', a.get('labels',{}).get('alertname'), a.get('status',{}).get('state'))
except Exception as e: print('  ', e)
" 2>&1
