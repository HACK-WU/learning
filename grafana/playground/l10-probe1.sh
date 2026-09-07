#!/bin/bash
echo "=== health ==="
curl -s --noproxy '*' http://localhost:3002/api/health | tr -d ' \n'
echo
echo
echo "=== datasources ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3002/api/datasources | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    for x in d: print(f\"  uid={x.get('uid'):12} name={x.get('name'):12} type={x.get('type'):12} editable={x.get('editable')}\")
except Exception as e: print('ERR',e)
"
echo
echo "=== dashboards search ==="
curl -s --noproxy '*' -u admin:admin 'http://localhost:3002/api/search?type=dash-db' | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    for x in d: print(f\"  uid={x.get('uid'):16} title={x.get('title'):28} folder={x.get('folderTitle')}\")
    print('  total:',len(d))
except Exception as e: print('ERR',e)
"
echo
echo "=== folders ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3002/api/folders | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    for x in d: print(f\"  uid={x.get('uid'):16} title={x.get('title')}\")
except Exception as e: print('ERR',e)
"
echo
echo "=== alert rules ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3002/api/ruler/grafana/api/v1/rules | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    n=0
    for ns,groups in d.items():
        for g in groups:
            for r in g.get('rules',[]):
                n+=1
                print(f\"  ns={ns} group={g.get('name')} rule={r.get('grafana_alert',{}).get('title')}\")
    print('  total rules:',n)
except Exception as e: print('ERR',e)
"
