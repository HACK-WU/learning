#!/bin/bash
set -u
echo "########## 端到端验证：告警真的会响吗 ##########"
echo
echo "前提：应用当前处于 FAULT_MODE=1（checkout P90 ≈ 3.5s，错误率 ≈ 6%）"
echo "预期：shop-p90-latency 与 shop-error-rate 应在 1~2 分钟内触发"
echo

echo "=== 1. 确认故障仍在（checkout P90）==="
curl -s --noproxy '*' -m 8 -G http://localhost:3110/api/v1/query --data-urlencode 'query=histogram_quantile(0.9, sum by (le, route) (rate(shop_request_duration_seconds_bucket[2m])))' 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']['result']
for r in sorted(d,key=lambda x:-float(x['value'][1]))[:3]:
    print('   ', r['metric'].get('route'), 'P90=', round(float(r['value'][1]),3),'s')
" 2>&1
echo

echo "=== 2. 等 100 秒（告警 for=1m + group_wait）==="
sleep 100
echo "  done"
echo

echo "=== 3. 告警规则当前状态 ==="
curl -s --noproxy '*' -u admin:admin 'http://localhost:3130/api/ruler/grafana/api/v1/rules' 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)
for g in d.get('data',{}).get('groups',[]):
    for r in g.get('rules',[]):
        print('  ', r.get('name'))
        print('     state =', r.get('state'), ' health =', r.get('health'))
        for a in r.get('alerts',[])[:2]:
            print('     alert:', a.get('state'), str(a.get('annotations',{}).get('summary',''))[:70])
" 2>&1
echo

echo "=== 4. Alertmanager 里的活跃告警 ==="
curl -s --noproxy '*' -u admin:admin 'http://localhost:3130/api/alertmanager/grafana/api/v2/alerts' 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  活跃告警数 =', len(d) if isinstance(d,list) else '?')
for a in (d if isinstance(d,list) else [])[:5]:
    L=a.get('labels',{})
    print('   ', L.get('alertname'), '| severity=', L.get('severity'), '| state=', a.get('status',{}).get('state'))
" 2>&1
echo

echo "=== 5. webhook 收到了吗（关键证据）==="
docker logs p3-webhook 2>&1 | tail -40
echo

echo "=== 6. 落盘的告警文件 ==="
ls -la /mnt/d/projects/learning/grafana/projects/从告警到定位/实现/webhook/out/ 2>&1 | head -10
