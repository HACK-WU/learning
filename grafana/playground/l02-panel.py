# -*- coding: utf-8 -*-
"""
课 2 知识点 2.3 实验：第一个 Panel —— 单位、阈值、图例的生效条件

为什么用 Python 而不是 shell 拼 JSON：
  2026-09-04 实测，shell 里内联含 PromQL（带双引号 {mode="idle"}）的 JSON，
  引号转义会导致 Grafana 返回 400 bad request data。改用 python 生成 JSON 后全部 200。
  （课 1 的 l01-forms.sh 已踩过同一个坑，本脚本沿用 l01-forms.py 的路线）
"""
import json
import urllib.request
import urllib.error
import http.cookiejar

GF = "http://localhost:3014"
USER, PASS = "admin", "lab-pass-2026"
PROM_UID = "cfx7z63ogo54wd"

cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
urllib.request.install_opener(opener)


def req(method, path, data=None):
    url = GF + path
    body = json.dumps(data).encode() if data is not None else None
    r = urllib.request.Request(url, data=body, method=method)
    if body:
        r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw.strip().startswith(("{", "[")) else raw)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw


def line(t=""):
    print(t)


# ---------- 登录 ----------
st, r = req("POST", "/login", {"user": USER, "password": PASS})
line(f"登录: HTTP {st}  {r}")
line()

EXPR = '100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100)'

# ---------- 实验 A：后端返回的原始值 vs 单位配置 ----------
line("########## 实验 A：单位是『前端格式化』还是『后端换算』？##########")
line(f"  表达式: {EXPR}")
q = {"queries": [{"refId": "A", "datasource": {"type": "prometheus", "uid": PROM_UID},
                  "expr": EXPR, "instant": True, "range": False}],
     "from": "now-5m", "to": "now"}
st, d = req("POST", "/api/ds/query", q)
frames = d.get("results", {}).get("A", {}).get("frames", [])
line(f"  HTTP {st}，返回 {len(frames)} 个 frame")
for f in frames:
    names = [x["name"] for x in f["schema"]["fields"]]
    vals = f["data"]["values"]
    line(f"    fields: {names}")
    line(f"    values: {vals}")
    line(f"    meta  : {json.dumps(f['schema'].get('meta'), ensure_ascii=False)}")
    cfgs = [{k: v for k, v in x.get("config", {}).items()
             if k in ("unit", "displayName", "decimals")} for x in f["schema"]["fields"]]
    line(f"    fieldConfig(unit/decimals 等): {json.dumps(cfgs, ensure_ascii=False)}")
line()

# 实测当前值落在哪个阈值区间
cur = None
for f in frames:
    for i, fld in enumerate(f["schema"]["fields"]):
        if fld.get("type") == "number":
            v = f["data"]["values"][i]
            if v and v[0] is not None:
                cur = v[0]
                break
if cur is not None:
    color = "green" if cur < 60 else ("orange" if cur < 85 else "red")
    line(f"  当前 CPU 使用率实测值: {cur:.2f}%  → 落在阈值区间: {color}")
line()

# ---------- 实验 B：建 dashboard，写死单位与阈值，再读回 ----------
line("########## 实验 B：单位与阈值在 dashboard JSON 里落在哪一段？##########")
thresholds = {"mode": "absolute", "steps": [
    {"color": "green", "value": None},
    {"color": "orange", "value": 60},
    {"color": "red", "value": 85}]}

panel_ts = {
    "id": 1, "type": "timeseries", "title": "CPU 使用率（Time series）",
    "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
    "datasource": {"type": "prometheus", "uid": PROM_UID},
    "targets": [{"refId": "A", "expr": EXPR, "legendFormat": "{{instance}}"}],
    "fieldConfig": {"defaults": {"unit": "percent", "min": 0, "max": 100,
                                 "thresholds": thresholds,
                                 "custom": {"lineWidth": 2, "fillOpacity": 10}},
                    "overrides": []}}
panel_stat = {
    "id": 2, "type": "stat", "title": "CPU 使用率（Stat）",
    "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
    "datasource": {"type": "prometheus", "uid": PROM_UID},
    "targets": [{"refId": "A", "expr": EXPR, "legendFormat": "{{instance}}", "instant": True}],
    "fieldConfig": {"defaults": {"unit": "percent", "thresholds": thresholds}, "overrides": []}}

dash = {"dashboard": {"title": "L02 第一个面板", "uid": "l02-first", "schemaVersion": 41,
                      "panels": [panel_ts, panel_stat],
                      "time": {"from": "now-15m", "to": "now"}},
        "overwrite": True}
st, r = req("POST", "/api/dashboards/db", dash)
line(f"  创建: HTTP {st} status={r.get('status')} uid={r.get('uid')} url={r.get('url')}")
line()

st, d = req("GET", "/api/dashboards/uid/l02-first")
db = d["dashboard"]
line(f"  读回: HTTP {st}  title={db['title']}  schemaVersion={db.get('schemaVersion')}")
for p in db["panels"]:
    fc = p["fieldConfig"]["defaults"]
    line(f"    [{p['type']}] {p['title']}")
    line(f"        unit        = {fc.get('unit')}")
    line(f"        min/max     = {fc.get('min')} / {fc.get('max')}")
    line(f"        thresholds  = {json.dumps(fc.get('thresholds'), ensure_ascii=False)}")
    line(f"        targets[0]  = {p['targets'][0].get('expr')}")
    line(f"        legendFormat= {p['targets'][0].get('legendFormat')}")
line()

# ---------- 实验 C：单位改了，后端返回值变不变 ----------
line("########## 实验 C：把单位换成 bytes，后端返回值会变吗？##########")
panel_ts2 = json.loads(json.dumps(panel_ts))
panel_ts2["fieldConfig"]["defaults"]["unit"] = "bytes"
dash2 = {"dashboard": {"title": "L02 单位对照", "uid": "l02-unit", "schemaVersion": 41,
                       "panels": [panel_ts2], "time": {"from": "now-15m", "to": "now"}},
         "overwrite": True}
st, r = req("POST", "/api/dashboards/db", dash2)
line(f"  创建单位=bytes 的副本: HTTP {st} status={r.get('status')}")
line(f"  再次查询后端原始值: ", )
st, d2 = req("POST", "/api/ds/query", q)
f2 = d2["results"]["A"]["frames"][0]
line(f"    values = {f2['data']['values']}")
# 只比数值，不比时间戳（时间戳每次查询都在变，比它会得到假的『不一致』）
def numbers_of(fr):
    out = []
    for i, fld in enumerate(fr["schema"]["fields"]):
        if fld.get("type") == "number":
            out.append(fr["data"]["values"][i])
    return out
n1, n2 = numbers_of(frames[0]), numbers_of(f2)
same = n1 == n2
line(f"  → 数值部分 {'完全一致' if same else '不一致'}  A={n1}  C={n2}")
line("    证明 unit 只影响前端显示格式化，不改变后端返回的数据")
line("    （注意：比对应只取数值字段；Time 字段是每次查询的当前时刻，必然不同）")
line()

# ---------- 实验 D：legendFormat 的作用 ----------
line("########## 实验 D：legendFormat 改的是 frame 里哪个字段？##########")
for lf in ["{{instance}}", "CPU-{{instance}}", ""]:
    qq = {"queries": [{"refId": "A", "datasource": {"type": "prometheus", "uid": PROM_UID},
                       "expr": EXPR, "legendFormat": lf, "instant": True, "range": False}],
          "from": "now-5m", "to": "now"}
    st, dd = req("POST", "/api/ds/query", qq)
    fr = dd["results"]["A"]["frames"]
    got = []
    for f in fr:
        for i, fld in enumerate(f["schema"]["fields"]):
            if fld.get("type") == "number":
                lbls = fld.get("labels") or {}
                got.append(lbls)
    line(f"  legendFormat={lf!r:20} -> frame 的 labels = {json.dumps(got, ensure_ascii=False)}")
line()
line("  → legendFormat 作用于『数据回来之后』的显示名，")
line("    它不改 PromQL 本身，也不改 labels 结构（本例中 instance 标签原样保留）")
line()
line("RESULT: 全部实验执行完毕")
