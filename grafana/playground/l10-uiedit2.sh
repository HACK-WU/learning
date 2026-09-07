#!/bin/bash
curl -s --noproxy '*' -u admin:admin http://localhost:3003/api/dashboards/uid/prov-dash-001 > /tmp/l10d2.json
python3 - <<'PY'
import json,urllib.request,urllib.error,base64
BASE='http://localhost:3003'
AUTH=base64.b64encode(b'admin:admin').decode()
d=json.load(open('/tmp/l10d2.json'))
dash=d['dashboard']
print('  before: title=%r version=%s' % (dash.get('title'),dash.get('version')))
dash['title']='EDITED BY UI (prov2)'
payload={'dashboard':dash,'message':'ui edit','overwrite':True}
data=json.dumps(payload).encode()
r=urllib.request.Request(BASE+'/api/dashboards/db',data=data,method='POST',
    headers={'Content-Type':'application/json','Authorization':'Basic '+AUTH})
try:
    with urllib.request.urlopen(r,timeout=30) as resp:
        b=json.loads(resp.read().decode())
        print('  SAVE http=%s version=%s status=%s' % (resp.status,b.get('version'),b.get('status')))
except urllib.error.HTTPError as e:
    print('  SAVE FAILED http=%s body=%s' % (e.code,e.read().decode()[:300]))
PY
echo
echo "=== read back ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3003/api/dashboards/uid/prov-dash-001 | python3 -c "
import sys,json;d=json.load(sys.stdin)
print('  title  =',d['dashboard'].get('title'))
print('  version=',d['dashboard'].get('version'))
"
echo
echo "=== restart prov2, see if file re-asserts ==="
docker restart grafana-prov2
for i in $(seq 1 60); do
  h=$(curl -s --noproxy '*' -m 5 http://localhost:3003/api/health)
  flat=$(printf '%s' "$h" | tr -d ' \n')
  case "$flat" in *'"database":"ok"'*) break;; esac
  sleep 3
done
curl -s --noproxy '*' -u admin:admin http://localhost:3003/api/dashboards/uid/prov-dash-001 | python3 -c "
import sys,json;d=json.load(sys.stdin)
print('  after restart: title=%r version=%s' % (d['dashboard'].get('title'),d['dashboard'].get('version')))
"
