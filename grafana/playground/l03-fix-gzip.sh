#!/usr/bin/env bash
# 修复：给 PromLab 数据源加 Accept-Encoding: identity，绕开 gzip 解析问题
# 幂等：已设置则跳过
set -u
cat > /tmp/l03probe/fixenv.py <<'PYEOF'
import json, urllib.request, http.cookiejar
GF='http://localhost:3001'
cj=http.cookiejar.CookieJar()
op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
op.open(urllib.request.Request(GF+'/login',
    data=json.dumps({"user":"admin","password":"admin"}).encode(),
    headers={'Content-Type':'application/json'}))
ds=[d for d in json.load(op.open(GF+'/api/datasources')) if d['name']=='PromLab'][0]
jd=ds.get('jsonData') or {}
if jd.get('httpHeaderName1')=='Accept-Encoding':
    print("  已设置过，跳过"); raise SystemExit(0)

body={"name":ds['name'],"type":ds['type'],"url":ds['url'],
      "access":ds['access'],"isDefault":ds['isDefault'],
      "jsonData":{"httpHeaderName1":"Accept-Encoding","httpHeaderValue1":"identity"}}
req=urllib.request.Request(f"{GF}/api/datasources/uid/{ds['uid']}",
    data=json.dumps(body).encode(), headers={'Content-Type':'application/json'}, method='PUT')
print("  更新 HTTP =", op.open(req).status)

qq={"refId":"A","datasource":{"type":"prometheus","uid":ds['uid']},
    "expr":'100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100)',
    "instant":True,"range":False}
d=json.load(op.open(urllib.request.Request(GF+'/api/ds/query',
    data=json.dumps({"queries":[qq],"from":"now-5m","to":"now"}).encode(),
    headers={'Content-Type':'application/json'})))
res=d['results'].get('A',{}); fr=res.get('frames',[])
nn=sum(len((f.get('data',{}).get('values') or [[]])[0]) for f in fr)
print(f"  验证查询 → 帧数={len(fr)} 点数={nn}")
PYEOF
python3 /tmp/l03probe/fixenv.py
