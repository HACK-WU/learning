#!/usr/bin/env bash
# 课 3 · 3.2 完整实验（环境已修复：Accept-Encoding: identity）
# 目标：①变量候选值来源 ②$host 注入效果 ③多值 All 写法 ④插值发生位置
set -u
cat > /tmp/l03probe/exp32.py <<'PYEOF'
import json, urllib.request, http.cookiejar, urllib.parse, time
GF='http://localhost:3001'
cj=http.cookiejar.CookieJar()
op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
op.open(urllib.request.Request(GF+'/login',
    data=json.dumps({"user":"admin","password":"admin"}).encode(),
    headers={'Content-Type':'application/json'}))
ds=[d for d in json.load(op.open(GF+'/api/datasources')) if d['name']=='PromLab'][0]
uid=ds['uid']

def cnt(expr, frm="now-5m", to="now"):
    qq={"refId":"A","datasource":{"type":"prometheus","uid":uid},
        "expr":expr,"instant":True,"range":False}
    d=json.load(op.open(urllib.request.Request(GF+'/api/ds/query',
        data=json.dumps({"queries":[qq],"from":frm,"to":to}).encode(),
        headers={'Content-Type':'application/json'})))
    res=d['results'].get('A',{}); fr=res.get('frames',[])
    nn=sum(len((f.get('data',{}).get('values') or [[]])[0]) for f in fr)
    return len(fr), nn, res

print("="*72)
print("【实验 1】变量候选值从哪来：Prometheus 的 instance 标签值")
print("="*72)
q=urllib.parse.quote('up{job="node"}')
j=json.load(op.open(f"{GF}/api/datasources/proxy/uid/{uid}/api/v1/query?query={q}"))
inst=sorted({r['metric']['instance'] for r in j['data']['result']})
for i in inst: print("   -", i)
print(f"  共 {len(inst)} 个 → 这就是 \$host 下拉框的选项来源")

print()
print("="*72)
print("【实验 2】反证：\$host 不替换 → 0 点；替换后 → 有数据")
print("="*72)
CUR=inst[0]
for e in ['up{instance="$host"}', f'up{{instance="{CUR}"}}']:
    nf,nn,_=cnt(e); print(f"  expr = {e:38s} → 帧数={nf} 点数={nn}")

print()
print("="*72)
print("【实验 3】多值 All 的正确写法：正则匹配 =~")
print("="*72)
allre="|".join(inst)
nf,nn,_=cnt(f'up{{instance=~"{allre}"}}')
print(f"  三台全选 up{{instance=~\"{allre[:28]}...\"}} → 帧数={nf} 点数={nn}")
nf,nn,_=cnt(f'up{{instance="{allre}"}}')
print(f"  错误写法（用 = 不用 =~）              → 帧数={nf} 点数={nn}  ← 0 点，写错就没数据")

print()
print("="*72)
print("【实验 4】变量写进 dashboard JSON 的哪个字段")
print("="*72)
dash={"dashboard":{
  "uid":"l03-var-final","title":"L03-变量最终版",
  "time":{"from":"now-1h","to":"now"},"schemaVersion":41,
  "templating":{"list":[{
     "name":"host","label":"主机","type":"query",
     "datasource":{"type":"prometheus","uid":uid},
     "query":'label_values(up{job="node"}, instance)',
     "refresh":1,"includeAll":True,"multi":False,"sort":1,
     "current":{"text":CUR,"value":CUR,"selected":True},
     "options":[{"text":i,"value":i,"selected":(i==CUR)} for i in inst],
     "definition":'label_values(up{job="node"}, instance)'}]},
  "panels":[{"id":1,"type":"timeseries","title":"主机存活 - $host",
    "gridPos":{"h":8,"w":12,"x":0,"y":0},
    "datasource":{"type":"prometheus","uid":uid},
    "targets":[{"refId":"A","datasource":{"type":"prometheus","uid":uid},
                "expr":'up{instance="$host"}',"editorMode":"code"}]}]},
  "overwrite":True}
r=op.open(urllib.request.Request(GF+'/api/dashboards/db',
    data=json.dumps(dash).encode(), headers={'Content-Type':'application/json'}))
print("  保存 HTTP =", r.status); json.load(r)
d=json.load(op.open(GF+'/api/dashboards/uid/l03-var-final'))
print("  dashboard 顶层键:", list(d['dashboard'].keys()))
for v in d['dashboard']['templating']['list']:
    print(f"  变量 {v['name']} 定义在 templating.list[0]")
    print(f"    name={v['name']} type={v['type']} query={v['query']}")
    print(f"    current={json.dumps(v.get('current'),ensure_ascii=False)}")
print("  面板 expr =", d['dashboard']['panels'][0]['targets'][0]['expr'])
print("  → expr 里仍是 $host 字面量！替换发生在渲染时，不是存储时")
PYEOF
python3 /tmp/l03probe/exp32.py
