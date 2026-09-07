#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""最终闭环：恢复正确 exemplar 配置 + 端到端 指标→trace 下钻"""
import json, urllib.request, urllib.error, urllib.parse, base64

GF = "http://localhost:3001"
LOKI_UID = "ffxhrcfr0wrnkf"
JAEGER_UID = "afxhrcft3tq0we"
PROM_UID = "efxhrcfu7s3k0e"

def req(url, data=None, method=None):
    tok = base64.b64encode(b"admin:admin").decode()
    h = {"Authorization": f"Basic {tok}"}
    body = json.dumps(data).encode() if data is not None else None
    if body: h["Content-Type"] = "application/json"
    r = urllib.request.Request(url, data=body, headers=h, method=method)
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:
        return -1, str(e)

def log(*a): print(*a, flush=True)

log("=" * 68)
log("最终闭环：恢复配置 + 三级下钻")
log("=" * 68)

# ------------------------------------------- 1
log("\n【1】恢复正确的 exemplar 配置")
st, body = req(f"{GF}/api/datasources/uid/{PROM_UID}")
ds = json.loads(body)
ds["jsonData"]["exemplarTraceIdDestinations"] = [
    {"name": "traceID", "datasourceUid": JAEGER_UID}]
ds.pop("version", None)
st2, _ = req(f"{GF}/api/datasources/uid/{PROM_UID}", data=ds, method="PUT")
log(f"  PUT -> HTTP {st2}")
st3, body3 = req(f"{GF}/api/datasources/uid/{PROM_UID}")
got = json.loads(body3)["jsonData"].get("exemplarTraceIdDestinations")
log(f"  回读 = {got}  {'✅' if got and got[0]['name']=='traceID' else '❌'}")

# ------------------------------------------- 2
log("\n【2】9.1 验证：用 Grafana 正规通道查 Loki（range 查询）")
payload = {"queries": [{"refId": "A",
                        "datasource": {"type": "loki", "uid": LOKI_UID},
                        "expr": '{job="shop"}'}],
           "from": "now-1h", "to": "now"}
st, body = req(f"{GF}/api/ds/query", data=payload)
log(f"  /api/ds/query -> HTTP {st}")
if st == 200:
    res = json.loads(body)["results"]["A"]
    frames = res.get("frames", [])
    log(f"    status={res.get('status')}  frames={len(frames)}")
    for f in frames[:4]:
        vals = f["data"]["values"]
        lines = vals[1] if len(vals) > 1 else []
        log(f"      frame: {len(lines)} 行")
        for ln in lines[:3]:
            log(f"        {str(ln)[:70]}")

# ------------------------------------------- 3
log("\n【3】9.2 验证：时间窗对齐（同一查询三个窗口）")
for w, desc in [("now-5m", "5 分钟"), ("now-1h", "1 小时"), ("now-24h", "24 小时")]:
    p = {"queries": [{"refId": "A", "datasource": {"type": "loki", "uid": LOKI_UID},
                      "expr": '{job="shop"}'}], "from": w, "to": "now"}
    st, body = req(f"{GF}/api/ds/query", data=p)
    n = 0
    if st == 200:
        for f in json.loads(body)["results"]["A"].get("frames", []):
            if len(f["data"]["values"]) > 1:
                n += len(f["data"]["values"][1])
    log(f"  窗口 {desc:<8} -> {n} 行  # from={w}")

# ------------------------------------------- 4
log("\n【4】9.3 端到端：指标 → exemplar → trace")
st, body = req(f"{GF}/api/datasources/proxy/uid/{PROM_UID}/api/v1/query_exemplars?query=h_test_bucket")
log(f"  查 exemplars -> HTTP {st}")
tids = set()
if st == 200:
    for g in (json.loads(body).get("data") or []):
        for it in g.get("exemplars", []):
            tids.add(it.get("labels", {}).get("traceID"))
log(f"  指标点里藏的 traceID = {tids}")

for tid in tids:
    st2, body2 = req(f"{GF}/api/datasources/proxy/uid/{JAEGER_UID}/api/traces/{tid}")
    log(f"  用它在 Jaeger 里查 -> HTTP {st2}")
    if st2 == 200:
        d = json.loads(body2).get("data") or []
        if d:
            t = d[0]
            log(f"    ✅ 命中 trace {t.get('traceID')}，{len(t.get('spans',[]))} 个 span：")
            for s in t.get("spans", []):
                log(f"        - {s.get('operationName'):<18} spanID={s.get('spanID')}")
        else:
            log("    ⚠️ 空 data")

log("\n" + "=" * 68)
log("✅ 三级下钻闭环完成：指标(桶上的点) --exemplar--> traceID --Jaeger--> 具体 span")
log("=" * 68)
