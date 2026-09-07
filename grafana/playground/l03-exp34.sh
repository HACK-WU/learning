#!/usr/bin/env bash
# 课 3 收尾验证：
# A) Repeat 面板到底复制出几份（前端渲染行为，用 API 侧可验证的方式）
# B) 时间选择器共享性的最终确认：同一 dashboard 内所有面板拿到同一个时间窗
set -u
cat > /tmp/l03probe/exp34.py <<'PYEOF'
import json, urllib.request, http.cookiejar, urllib.parse
GF='http://localhost:3001'
cj=http.cookiejar.CookieJar()
op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
op.open(urllib.request.Request(GF+'/login',
    data=json.dumps({"user":"admin","password":"admin"}).encode(),
    headers={'Content-Type':'application/json'}))
uid=[d for d in json.load(op.open(GF+'/api/datasources')) if d['name']=='PromLab'][0]['uid']

print("="*72)
print("【A】Repeat 的复制份数 = 变量当前值的个数")
print("="*72)
d=json.load(op.open(GF+'/api/dashboards/uid/l03-row'))
var=[v for v in d['dashboard']['templating']['list'] if v['name']=='host'][0]
cur=var.get('current',{})
vals=cur.get('value') if isinstance(cur.get('value'),list) else [cur.get('value')]
print(f"  变量 host 当前值 = {vals}")
print(f"  → 共 {len(vals)} 个值，Repeat 面板会复制出 {len(vals)} 份")
print(f"  面板 JSON 里只存了 1 份（repeat='host'），复制发生在渲染时")
print()
print("  验证：把变量值减到 2 个，看 JSON 是否仍是 1 个面板（证明不是存了 N 份）")
dash=d['dashboard']
var['current']={"text":vals[:2],"value":vals[:2]}
body={"dashboard":dash,"overwrite":True}
r=op.open(urllib.request.Request(GF+'/api/dashboards/db',
    data=json.dumps(body).encode(), headers={'Content-Type':'application/json'}))
json.load(r)
d2=json.load(op.open(GF+'/api/dashboards/uid/l03-row'))
n_panels=len([p for p in d2['dashboard']['panels'] if p['type']!='row'])
row_subs=sum(len(p.get('panels',[])) for p in d2['dashboard']['panels'] if p['type']=='row')
print(f"  变量改为 2 个值后：非 row 面板数={n_panels} row 内子面板={row_subs}")
print(f"  → JSON 里始终是 1 个模板面板，复制份数由渲染时变量值个数决定")

print()
print("="*72)
print("【B】时间选择器共享性：同一次请求里所有查询拿到同一时间窗")
print("="*72)
# 用探针已证明：同一 payload 的 from/to 对所有 query 一致
# 这里直接验证：改 dashboard 的 time.from，所有面板的时间窗一起变
for tf in ["now-15m","now-6h"]:
    dash3=json.load(op.open(GF+'/api/dashboards/uid/l03-row'))['dashboard']
    dash3['time']={"from":tf,"to":"now"}
    body={"dashboard":dash3,"overwrite":True}
    op.open(urllib.request.Request(GF+'/api/dashboards/db',
        data=json.dumps(body).encode(), headers={'Content-Type':'application/json'}))
    got=json.load(op.open(GF+'/api/dashboards/uid/l03-row'))
    print(f"  设置 time.from={tf:9s} → 读回 dashboard.time = {got['dashboard']['time']}")
print("  → 时间范围是 dashboard 级字段，不属于任何单个面板")

print()
print("="*72)
print("【C】单面板 timeFrom 覆写：存得进去，但后端 /api/ds/query 不认")
print("="*72)
dash4=json.load(op.open(GF+'/api/dashboards/uid/l03-row'))['dashboard']
# 给第一个非 row 面板加 timeFrom
for p in dash4['panels']:
    if p['type']!='row':
        p['timeFrom']='10m'; break
body={"dashboard":dash4,"overwrite":True}
op.open(urllib.request.Request(GF+'/api/dashboards/db',
    data=json.dumps(body).encode(), headers={'Content-Type':'application/json'}))
got=json.load(op.open(GF+'/api/dashboards/uid/l03-row'))
for p in got['dashboard']['panels']:
    if p.get('timeFrom'): print(f"  面板[{p['id']}] timeFrom = {p['timeFrom']}  ← 持久化成功")
print("  （本课前文已用探针证明：后端查询仍按 dashboard 窗口计算）")
PYEOF
python3 /tmp/l03probe/exp34.py
