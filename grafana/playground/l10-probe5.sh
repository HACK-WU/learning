#!/bin/bash
curl -s --noproxy '*' -u admin:admin http://localhost:3002/api/dashboards/uid/prov-dash-001 > /tmp/l10d.json
python3 - <<'PY'
import json,urllib.request,urllib.error,base64
BASE='http://localhost:3002'
AUTH=base64.b64encode(b'admin:admin').decode()
d=json.load(open('/tmp/l10d.json'))['dashboard']
d['title']='EDITED BY UI'
payload={'dashboard':d,'message':'ui edit','overwrite':True}
data=json.dumps(payload).encode()
r=urllib.request.Request(BASE+'/api/dashboards/db',data=data,method='POST',
    headers={'Content-Type':'application/json','Authorization':'Basic '+AUTH})
try:
    with urllib.request.urlopen(r,timeout=30) as resp:
        print('OK',resp.status,resp.read().decode()[:500])
except urllib.error.HTTPError as e:
    print('HTTP',e.code)
    print(e.read().decode()[:1500])
PY
