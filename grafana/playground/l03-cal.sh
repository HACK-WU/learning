#!/usr/bin/env bash
# 课 3 · 3.1 标定实验
# 目的 1：确认 calculatedMinStep 与请求窗口的对应关系（把它变成"时间窗口探针"）
# 目的 2：用该探针检验 panel 级 timeFrom 覆写是否被后端接受
set -u
cat > /tmp/l03-cal.py <<'PYEOF'
import json, urllib.request, http.cookiejar, time

GF='http://localhost:3001'
cj=http.cookiejar.MozillaCookieJar()
op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
op.open(urllib.request.Request(GF+'/login',
    data=json.dumps({"user":"admin","password":"admin"}).encode(),
    headers={'Content-Type':'application/json'}))
uid=json.load(op.open(GF+'/api/datasources'))[0]['uid']

def query(qs, frm, to):
    payload={"queries":qs,"from":str(frm),"to":str(to)}
    return json.load(op.open(urllib.request.Request(GF+'/api/ds/query',
        data=json.dumps(payload).encode(), headers={'Content-Type':'application/json'})))

def step_of(d, k):
    res=d['results'].get(k,{})
    if 'error' in res: return 'ERR:'+str(res['error'])[:60]
    fr=res.get('frames') or []
    if not fr: return 'no-frame'
    return fr[0].get('schema',{}).get('meta',{}).get('custom',{}).get('calculatedMinStep')

now=int(time.time()*1000)

print("### 标定：固定 maxDataPoints=1000 / intervalMs=1000，只改请求窗口 ###")
print(f"{'窗口':>8} | {'calculatedMinStep':>18}")
print("-"*32)
base={"datasource":{"type":"prometheus","uid":uid},
      "expr":'up{job="node"}',"instant":False,"range":True,
      "intervalMs":1000,"maxDataPoints":1000}
for label,secs in [("5m",300),("10m",600),("1h",3600),("6h",21600),("24h",86400)]:
    d=query([dict(base, refId="A")], now-secs*1000, now)
    s=step_of(d,"A")
    print(f"{label:>8} | {str(s)+' ms':>18}  ({s/1000 if isinstance(s,int) else '?'} s)")

print()
print("### 用探针检验 timeFrom：dashboard 窗口 6h，B 声明 timeFrom='10m' ###")
qs=[dict(base, refId="A"), dict(base, refId="B", timeFrom="10m")]
d=query(qs, now-6*3600*1000, now)
print(f"  A（跟随 dashboard，窗口 6h）      step = {step_of(d,'A')} ms")
print(f"  B（timeFrom='10m' 期望窗口 10m）  step = {step_of(d,'B')} ms")
print(f"  10m 窗口的基准 step 应为 = {step_of(query([dict(base,refId='A')], now-600*1000, now),'A')} ms")
print()
print("  结论判定：若 B 的 step 与 A 相同 → 后端未接受 timeFrom（timeFrom 是前端概念）")
PYEOF
python3 /tmp/l03-cal.py
