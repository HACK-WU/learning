#!/usr/bin/env bash
set -u
echo "=========================================="
echo " 课 5 环境探测"
echo "=========================================="

echo ""
echo "--- [1] 容器状态 ---"
docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'grafana|NAMES'

echo ""
echo "--- [2] Grafana health ---"
curl -s http://localhost:3001/api/health | tr -d ' \n'
echo ""

echo ""
echo "--- [3] 数据源 ---"
curl -s -u admin:admin http://localhost:3001/api/datasources \
  | python3 -c "
import sys,json
ds=json.load(sys.stdin)
print('  数据源数：%d'%len(ds))
for d in ds:
    print('    %-12s uid=%s type=%s url=%s'%(d['name'],d['uid'],d['type'],d.get('url','')))
"

echo ""
echo "--- [4] Prometheus targets（应 3 台 node）---"
curl -s 'http://localhost:9201/api/v1/targets?state=active' \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    print('  %-24s %-14s health=%s'%(t['labels'].get('instance'), t['labels'].get('job'), t['health']))
" 2>&1 | head -12

echo ""
echo "--- [5] 复现课 1 伏笔：node_cpu 返回多少 frame？---"
cat > /tmp/l05q.json <<'JSON'
{
  "queries": [{
    "refId": "A",
    "datasource": {"type": "prometheus", "uid": "afx7x6dx803y8e"},
    "expr": "rate(node_cpu_seconds_total{mode=\"idle\"}[2m])",
    "range": true, "instant": false,
    "intervalMs": 15000, "maxDataPoints": 50
  }],
  "from": "now-5m", "to": "now"
}
JSON
curl -s -u admin:admin -X POST http://localhost:3001/api/ds/query \
  -H 'Content-Type: application/json' --data @/tmp/l05q.json \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
r=d.get('results',{}).get('A') or {}
frs=r.get('frames') or []
print('  frame 数 = %d'%len(frs))
print()
for i,f in enumerate(frs[:6]):
    sch=f.get('schema',{})
    fields=sch.get('fields',[])
    labels=f.get('schema',{}).get('fields',[{}])
    # 取每个 frame 的 labels
    fl=f.get('schema',{}).get('fields',[])
    lab=''
    for fl2 in fl:
        l=(fl2.get('labels') or {})
        if l:
            lab=', '.join('%s=%s'%(k,v) for k,v in l.items())
            break
    print('  frame[%d]: fields=%d  values=%s  labels=%s'%(
        i, len(fl), 'yes' if f.get('data',{}).get('values') else 'no', lab))
if len(frs)>6: print('  ... 还有 %d 个 frame'%(len(frs)-6))
"

echo ""
echo "=========================================="
echo " 探测完成"
echo "=========================================="
