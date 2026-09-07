#!/usr/bin/env bash
# 课 3 · 3.3：Row 与折叠、面板复用（Repeat）、JSON Model 初见
set -u
cat > /tmp/l03probe/exp33.py <<'PYEOF'
import json, urllib.request, http.cookiejar, urllib.parse
GF='http://localhost:3001'
cj=http.cookiejar.CookieJar()
op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
op.open(urllib.request.Request(GF+'/login',
    data=json.dumps({"user":"admin","password":"admin"}).encode(),
    headers={'Content-Type':'application/json'}))
uid=[d for d in json.load(op.open(GF+'/api/datasources')) if d['name']=='PromLab'][0]['uid']

q=urllib.parse.quote('up{job="node"}')
j=json.load(op.open(f"{GF}/api/datasources/proxy/uid/{uid}/api/v1/query?query={q}"))
inst=sorted({r['metric']['instance'] for r in j['data']['result']})

print("="*72)
print("【实验 1】Row 是什么：一种特殊的 panel（type='row'）")
print("="*72)
dash={"dashboard":{
  "uid":"l03-row","title":"L03-Row与复用",
  "time":{"from":"now-1h","to":"now"},"schemaVersion":41,
  "templating":{"list":[{
     "name":"host","type":"custom","query":"grafana-node:9100,grafana-node2:9100,grafana-node3:9100",
     "current":{"text":["grafana-node:9100","grafana-node2:9100","grafana-node3:9100"],
                "value":["grafana-node:9100","grafana-node2:9100","grafana-node3:9100"]},
     "options":[],"includeAll":False,"multi":True}]},
  "panels":[
    {"id":10,"type":"row","title":"第一行：整体视图","collapsed":False,
     "gridPos":{"h":1,"w":24,"x":0,"y":0},"panels":[]},
    {"id":1,"type":"stat","title":"机器总数",
     "gridPos":{"h":4,"w":6,"x":0,"y":1},
     "datasource":{"type":"prometheus","uid":uid},
     "targets":[{"refId":"A","datasource":{"type":"prometheus","uid":uid},
                 "expr":'count(up{job="node"})',"editorMode":"code"}]},
    {"id":20,"type":"row","title":"第二行：分主机明细","collapsed":False,
     "gridPos":{"h":1,"w":24,"x":0,"y":5},"panels":[]},
    # Repeat 面板：按 $host 每个值复制一份
    {"id":2,"type":"timeseries","title":"$host 的 CPU",
     "gridPos":{"h":8,"w":12,"x":0,"y":6},
     "repeat":"host","repeatDirection":"h","maxPerRow":2,
     "datasource":{"type":"prometheus","uid":uid},
     "targets":[{"refId":"A","datasource":{"type":"prometheus","uid":uid},
                 "expr":'100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle",instance="$host"}[2m])) * 100)',
                 "editorMode":"code","legendFormat":"{{instance}}"}]}
  ]},
  "overwrite":True}
r=op.open(urllib.request.Request(GF+'/api/dashboards/db',
    data=json.dumps(dash).encode(), headers={'Content-Type':'application/json'}))
print("  保存 HTTP =", r.status); json.load(r)

d=json.load(op.open(GF+'/api/dashboards/uid/l03-row'))
print("  读回面板清单：")
for p in d['dashboard']['panels']:
    extra=""
    if p.get('repeat'): extra=f"  repeat={p['repeat']} repeatDirection={p.get('repeatDirection')} maxPerRow={p.get('maxPerRow')}"
    print(f"    [{p['id']}] type={p['type']:12s} title={p.get('title')!r}{extra}")

print()
print("="*72)
print("【实验 2】Row 折叠的真实含义：collapsed=true 时，子面板进 row.panels")
print("="*72)
# 构造一个 collapsed 的 row（Grafana 的约定：折叠时子面板移到 row.panels 里）
dash2=json.loads(json.dumps(d['dashboard']))
for p in dash2['panels']:
    if p['id']==20:
        p['collapsed']=True
        p['panels']=[x for x in dash2['panels'] if x.get('gridPos',{}).get('y',0)>=6]
dash2['panels']=[p for p in dash2['panels']
                 if p['id'] in (10,1,20) ]
body={"dashboard":dash2,"overwrite":True,"message":"折叠第二行"}
r=op.open(urllib.request.Request(GF+'/api/dashboards/db',
    data=json.dumps(body).encode(), headers={'Content-Type':'application/json'}))
print("  保存 HTTP =", r.status); json.load(r)
d2=json.load(op.open(GF+'/api/dashboards/uid/l03-row'))
for p in d2['dashboard']['panels']:
    sub=f"  内含 {len(p.get('panels',[]))} 个子面板" if p['type']=='row' else ""
    print(f"    [{p['id']}] type={p['type']:12s} collapsed={p.get('collapsed')} title={p.get('title')!r}{sub}")
    for sp in p.get('panels',[]):
        print(f"         └─ 子面板 [{sp['id']}] {sp.get('title')!r}")

print()
print("="*72)
print("【实验 3】JSON Model 全景：一个 dashboard 由哪几段构成")
print("="*72)
top=d2['dashboard']
print("  顶层字段：")
for k in top:
    v=top[k]
    if k=='panels':   s=f"{len(v)} 个面板"
    elif k=='templating': s=f"{len(v.get('list',[]))} 个变量"
    elif isinstance(v,(str,int,bool,type(None))): s=repr(v)[:60]
    else: s=json.dumps(v,ensure_ascii=False)[:60]
    print(f"    {k:16s} = {s}")
print()
print("  变量定义所在路径：dashboard.templating.list[]")
print("  面板定义所在路径：dashboard.panels[]  （折叠时嵌套在 row.panels[]）")
PYEOF
python3 /tmp/l03probe/exp33.py
