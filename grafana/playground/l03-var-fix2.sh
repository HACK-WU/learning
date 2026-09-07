#!/usr/bin/env bash
# 课 3 · 3.2 完整验证（代理路径已修正为 /api/datasources/proxy/uid/{uid}）
set -u
cat > /tmp/l03probe/fix2.py <<'PYEOF'
import json, urllib.request, http.cookiejar, urllib.parse, time
GF='http://localhost:3001'
cj=http.cookiejar.MozillaCookieJar()
op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
op.open(urllib.request.Request(GF+'/login',
    data=json.dumps({"user":"admin","password":"admin"}).encode(),
    headers={'Content-Type':'application/json'}))
ds=[x for x in json.load(op.open(GF+'/api/datasources')) if x['name']=='PromLab'][0]
uid=ds['uid']

print("="*72)
print("【1】变量候选值从哪来：Prometheus 的 instance 标签值")
print("="*72)
q=urllib.parse.quote('up{job="node"}')
j=json.load(op.open(f"{GF}/api/datasources/proxy/uid/{uid}/api/v1/query?query={q}"))
inst=sorted({r['metric']['instance'] for r in j['data']['result']})
for i in inst: print("   -", i)
print(f"  共 {len(inst)} 个 → 这就是下拉框的选项来源")

print()
print("="*72)
print("【2】把变量写进 dashboard 并持久化（current + options）")
print("="*72)
CUR=inst[0]
dash={"dashboard":{
  "uid":"l03-var-e2e","title":"L03-变量端到端",
  "time":{"from":"now-1h","to":"now"},"schemaVersion":41,
  "templating":{"list":[{
     "name":"host","label":"主机","type":"query",
     "datasource":{"type":"prometheus","uid":uid},
     "query":'label_values(up{job="node"}, instance)',
     "refresh":1,"includeAll":False,"multi":False,"sort":1,
     "current":{"text":CUR,"value":CUR,"selected":True},
     "options":[{"text":i,"value":i,"selected":(i==CUR)} for i in inst],
     "definition":'label_values(up{job="node"}, instance)'}]},
  "panels":[{"id":1,"type":"timeseries","title":"主机 $host 的存活状态",
    "gridPos":{"h":8,"w":12,"x":0,"y":0},
    "datasource":{"type":"prometheus","uid":uid},
    "targets":[{"refId":"A","datasource":{"type":"prometheus","uid":uid},
                "expr":'up{instance="$host"}',"editorMode":"code"}]}]},
  "overwrite":True}
r=op.open(urllib.request.Request(GF+'/api/dashboards/db',
    data=json.dumps(dash).encode(), headers={'Content-Type':'application/json'}))
print("  保存 HTTP =", r.status); json.load(r)
d=json.load(op.open(GF+'/api/dashboards/uid/l03-var-e2e'))
for v in d['dashboard']['templating']['list']:
    print(f"  变量 {v['name']}: current={json.dumps(v.get('current'),ensure_ascii=False)}")
    print(f"    options = {json.dumps([o.get('value') for o in v.get('options',[])],ensure_ascii=False)}")

print()
print("="*72)
print("【3】反证：不替换就查不到数据，替换后能查到")
print("="*72)
now=int(time.time()*1000)
def cnt(expr):
    payload={"queries":[{"refId":"A","datasource":{"type":"prometheus","uid":uid},
              "expr":expr,"instant":True,"range":False}],
             "from":str(now-3600000),"to":str(now)}
    d3=json.load(op.open(urllib.request.Request(GF+'/api/ds/query',
        data=json.dumps(payload).encode(), headers={'Content-Type':'application/json'})))
    res=d3['results']['A']; n=0
    for f in res.get('frames',[]):
        v=f.get('data',{}).get('values') or []
        n+=len(v[0]) if v else 0
    return n
for e in ['up{instance="$host"}', f'up{{instance="{CUR}"}}']:
    print(f"  expr = {e:38s} → 点数 = {cnt(e)}")

print()
print("="*72)
print("【4】多值 All 的正确写法：instance=~\"(...)\" 而不是 =")
print("="*72)
allre="|".join(inst)
for e in [f'up{{instance=~"{allre}"}}', 'up{instance=~"$host"}']:
    print(f"  expr = {e[:60]:60s} → 点数 = {cnt(e)}")
PYEOF
python3 /tmp/l03probe/fix2.py
