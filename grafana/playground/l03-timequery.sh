#!/usr/bin/env bash
# 课 3 · 知识点 3.1：Dashboard 与 Panel 的关系 —— 时间选择器是共享的
# 目标：实证 (a) 时间范围在 dashboard 级下发 (b) 单 panel 的"相对时间覆写"是什么行为
set -u
GF=http://localhost:3001
J=/tmp/gf-l03-cookie.txt
rm -f $J
curl -s -c $J -X POST $GF/login -H 'Content-Type: application/json' \
  -d '{"user":"admin","password":"admin"}' -o /dev/null

DS_UID=$(curl -s -b $J $GF/api/datasources \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(d[0]['uid'])")
echo "DS uid=$DS_UID"
echo

# 用相对时间 from=now-6h to=now，注意 Grafana 后端会把它解析成绝对毫秒
echo "=== 实验 1：一个 dashboard 里放 3 个 panel，用同一段时间范围 ==="
cat > /tmp/l03-time1.py <<PYEOF
import json, urllib.request, http.cookiejar, time

GF='http://localhost:3001'
cj=http.cookiejar.MozillaCookieJar()
op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
op.open(urllib.request.Request(GF+'/login',
    data=json.dumps({"user":"admin","password":"admin"}).encode(),
    headers={'Content-Type':'application/json'}))
dss=json.load(op.open(GF+'/api/datasources'))
uid=dss[0]['uid']

# 三个 panel，查询相同指标但 refId 不同
panels=[]
for i,ref in enumerate(['A','B','C'],start=1):
    panels.append({
      "id": i, "type":"timeseries", "title": f"panel-{ref}",
      "gridPos":{"h":8,"w":8,"x":(i-1)*8,"y":0},
      "datasource":{"type":"prometheus","uid":uid},
      "targets":[{"refId":ref,"datasource":{"type":"prometheus","uid":uid},
                  "expr":"up{job=\"node\"}","editorMode":"code"}]
    })

dash={
  "dashboard":{
    "uid":"l03-time-shared",
    "title":"L03-时间选择器共享性验证",
    "time":{"from":"now-6h","to":"now"},
    "timezone":"browser",
    "schemaVersion":41,
    "panels":panels,
    "templating":{"list":[]}
  },
  "overwrite":True
}
r=op.open(urllib.request.Request(GF+'/api/dashboards/db',
    data=json.dumps(dash).encode(),
    headers={'Content-Type':'application/json'}))
print("create dashboard HTTP =", r.status)
json.load(r)
print("已建 dashboard：l03-time-shared，含 3 个 panel（A/B/C）")
PYEOF
python3 /tmp/l03-time1.py
echo

echo "=== 实验 2：用相对时间 now-6h~now 查询，观察 Grafana 下发给 Prometheus 的 start/end ==="
cat > /tmp/l03-time2.py <<PYEOF
import json, urllib.request, http.cookiejar

GF='http://localhost:3001'
cj=http.cookiejar.MozillaCookieJar()
op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
op.open(urllib.request.Request(GF+'/login',
    data=json.dumps({"user":"admin","password":"admin"}).encode(),
    headers={'Content-Type':'application/json'}))
dss=json.load(op.open(GF+'/api/datasources'))
uid=dss[0]['uid']

# 关键：这里 from/to 我们用绝对毫秒，模拟前端解析后的值
import time
now_ms=int(time.time()*1000)
payload={
 "queries":[
   {"refId":"A","datasource":{"type":"prometheus","uid":uid},
    "expr":'up{job="node"}',"instant":False,"range":True,"intervalMs":60000,"maxDataPoints":100},
   {"refId":"B","datasource":{"type":"prometheus","uid":uid},
    "expr":'up{job="node"}',"instant":False,"range":True,"intervalMs":60000,"maxDataPoints":100},
   {"refId":"C","datasource":{"type":"prometheus","uid":uid},
    "expr":'up{job="node"}',"instant":False,"range":True,"intervalMs":60000,"maxDataPoints":100}
 ],
 "from":str(now_ms-6*3600*1000),
 "to":str(now_ms)
}
r=op.open(urllib.request.Request(GF+'/api/ds/query',
    data=json.dumps(payload).encode(),
    headers={'Content-Type':'application/json'}))
d=json.load(r)
print("=== 一次 HTTP 请求里三个查询的 executedQueryString ===")
for k in ['A','B','C']:
    res=d['results'].get(k,{})
    for f in res.get('frames',[]):
        m=f.get('schema',{}).get('meta',{}).get('custom',{})
        print(f"  refId={k}  start={m.get('start')}  end={m.get('end')}  step={m.get('calculatedMinStep')}")
        ts=f['schema']['fields'][0].get('values') if f['schema']['fields'] else None
PYEOF
python3 /tmp/l03-time2.py
echo

echo "=== 实验 3：给单个 panel 加 timeFrom（相对时间覆写），看它是否独立 ==="
cat > /tmp/l03-time3.py <<PYEOF
import json, urllib.request, http.cookiejar, time

GF='http://localhost:3001'
cj=http.cookiejar.MozillaCookieJar()
op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
op.open(urllib.request.Request(GF+'/login',
    data=json.dumps({"user":"admin","password":"admin"}).encode(),
    headers={'Content-Type':'application/json'}))
dss=json.load(op.open(GF+'/api/datasources'))
uid=dss[0]['uid']

now_ms=int(time.time()*1000)
# A 用 dashboard 时间；B 覆写为 now-1h
payload={
 "queries":[
   {"refId":"A","datasource":{"type":"prometheus","uid":uid},
    "expr":'up{job="node"}',"instant":False,"range":True,"intervalMs":60000,"maxDataPoints":100},
   {"refId":"B","datasource":{"type":"prometheus","uid":uid},
    "expr":'up{job="node"}',"instant":False,"range":True,"intervalMs":60000,"maxDataPoints":100,
    "timeFrom":"1h"}
 ],
 "from":str(now_ms-6*3600*1000),
 "to":str(now_ms)
}
r=op.open(urllib.request.Request(GF+'/api/ds/query',
    data=json.dumps(payload).encode(),
    headers={'Content-Type':'application/json'}))
d=json.load(r)
print("=== 同一请求内，A 与 B 的时间窗口 ===")
for k in ['A','B']:
    res=d['results'].get(k,{})
    if 'error' in res:
        print(f"  refId={k}  ERROR: {res['error']}"); continue
    for f in res.get('frames',[]):
        m=f.get('schema',{}).get('meta',{}).get('custom',{})
        st,en=m.get('start'),m.get('end')
        span_h=(en-st)/3600000 if (st and en) else None
        print(f"  refId={k}  start={st}  end={en}  跨度={span_h:.2f} 小时")
PYEOF
python3 /tmp/l03-time3.py
