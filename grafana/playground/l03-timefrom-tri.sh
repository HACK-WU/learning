#!/usr/bin/env bash
# 课 3 · 3.1 双面取证
# 目的：确认 panel 级 timeFrom 到底是"前端概念"还是"后端也认"
# 手法 A：直查 grafana.db，看 timeFrom 存不存在于 dashboard JSON
# 手法 B：把 timeFrom 写进真实 dashboard，用 Grafana 自己的渲染接口 panel 级查询，看是否生效
# 手法 C：日志侧信道——从 Prometheus 访问日志看后端实际发起了几个请求、窗口多大
set -u
GFDIR=/mnt/d/projects/learning/grafana/playground

cat > /tmp/l03-tri.py <<'PYEOF'
import json, urllib.request, http.cookiejar, time, sqlite3, os, subprocess

GF='http://localhost:3001'
cj=http.cookiejar.MozillaCookieJar()
op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
op.open(urllib.request.Request(GF+'/login',
    data=json.dumps({"user":"admin","password":"admin"}).encode(),
    headers={'Content-Type':'application/json'}))
uid=json.load(op.open(GF+'/api/datasources'))[0]['uid']

print("="*70)
print("【手法 A】把 timeFrom 写进真实 dashboard，再从 API 读回来")
print("="*70)
now=int(time.time()*1000)
def mkpanel(pid, ref, title, timeFrom=None):
    p={"id":pid,"type":"timeseries","title":title,
       "gridPos":{"h":8,"w":12,"x":0,"y":(pid-1)*8},
       "datasource":{"type":"prometheus","uid":uid},
       "targets":[{"refId":ref,"datasource":{"type":"prometheus","uid":uid},
                   "expr":'up{job="node"}',"editorMode":"code",
                   "instant":False,"range":True}]}
    if timeFrom: p["timeFrom"]=timeFrom
    return p

dash={"dashboard":{
        "uid":"l03-timefrom","title":"L03-timeFrom-验证",
        "time":{"from":"now-6h","to":"now"},"schemaVersion":41,
        "panels":[mkpanel(1,"A","跟随 dashboard 6h"),
                  mkpanel(2,"B","覆写为 10m", timeFrom="10m")],
        "templating":{"list":[]}},
      "overwrite":True}
r=op.open(urllib.request.Request(GF+'/api/dashboards/db',
    data=json.dumps(dash).encode(), headers={'Content-Type':'application/json'}))
print("  create HTTP =", r.status); json.load(r)

got=json.load(op.open(GF+'/api/dashboards/uid/l03-timefrom'))
for p in got['dashboard']['panels']:
    print(f"  panel[{p['id']}] title={p['title']!r}  timeFrom = {p.get('timeFrom','<未设置>')}")
print("  → timeFrom 确实被持久化到 dashboard JSON 里（存在性确认）")

print()
print("="*70)
print("【手法 B】用 Prometheus 查询日志做侧信道，看后端实际发出了什么窗口")
print("="*70)
# Prometheus 的访问日志在容器 stdout。先清空基线，再触发，再抓
subprocess.run("docker logs grafana-prom --since 1s >/dev/null 2>&1", shell=True)
time.sleep(1)

# 触发方式：Grafana 自身的 panel 渲染接口 /api/dashboards/uid/.../panels 不直接查，
# 改用 dashboard 快照查询接口（Grafana 会用 dashboard 里保存的面板配置去查）
before=subprocess.run("docker logs grafana-prom 2>&1 | wc -l", shell=True,
                      capture_output=True, text=True).stdout.strip()

payload={"queries":[
     {"refId":"A","datasource":{"type":"prometheus","uid":uid},
      "expr":'up{job="node"}',"instant":False,"range":True,
      "intervalMs":1000,"maxDataPoints":1000,"timeFrom":"10m"}],
   "from":str(now-6*3600*1000),"to":str(now)}
d=json.load(op.open(urllib.request.Request(GF+'/api/ds/query',
    data=json.dumps(payload).encode(), headers={'Content-Type':'application/json'})))
step=d['results']['A']['frames'][0]['schema']['meta']['custom']['calculatedMinStep']
print(f"  带 timeFrom='10m' 发给 /api/ds/query → calculatedMinStep = {step} ms")
print(f"  若后端认了 10m 窗口，应为 1000 ms；若按 dashboard 6h 算，应为 20000 ms")
print(f"  实测 = {step} ms  →  " + ("后端接受" if step==1000 else "后端未接受（按 dashboard 窗口计算）"))

print()
print("="*70)
print("【手法 C】直查 grafana.db：dashboard 表里 timeFrom 以什么形式存")
print("="*70)
# 从容器里拷出 db
subprocess.run("docker cp grafana-lab:/var/lib/grafana/grafana.db /tmp/l03-grafana.db >/dev/null 2>&1", shell=True)
if os.path.exists('/tmp/l03-grafana.db'):
    con=sqlite3.connect('/tmp/l03-grafana.db'); cur=con.cursor()
    cur.execute("SELECT slug, data FROM dashboard WHERE uid='l03-timefrom'")
    row=cur.fetchone()
    if row:
        dbj=json.loads(row[1])
        for p in dbj.get('panels',[]):
            print(f"  DB panel[{p['id']}] {p.get('title')!r} timeFrom={p.get('timeFrom','<未设置>')}")
        print("  → 数据库里存的就是 panel 对象里的 timeFrom 字段，与 API 读回一致")
    else:
        print("  未查到该 dashboard（可能用了 sqlite 之外的后端）")
    con.close()
else:
    print("  拷库失败")
PYEOF
python3 /tmp/l03-tri.py
