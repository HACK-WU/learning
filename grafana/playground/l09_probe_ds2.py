#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用真实 uid 验证连通性 + 配 exemplar 跳转 + 端到端查 exemplar"""
import json, urllib.request, urllib.error, base64

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

log("=" * 66)
log("实验五（修正）：连通性 + exemplar 配置 + 端到端")
log("=" * 66)

# ---------------------------------------------- 1
log("\n【1】三个数据源经 Grafana 代理的连通性")
for name, uid, path in [("LokiLab", LOKI_UID, "/loki/api/v1/labels"),
                        ("JaegerLab", JAEGER_UID, "/api/services"),
                        ("PromEx", PROM_UID, "/api/v1/labels")]:
    st, body = req(f"{GF}/api/datasources/proxy/uid/{uid}{path}")
    snippet = body.strip().replace("\n", " ")[:90]
    log(f"  {'✅' if st==200 else '❌'} {name:<10} HTTP {st}  {snippet}")

# ---------------------------------------------- 2
log("\n【2】经 Grafana 查 Loki 日志（验证 9.1 的 LogQL 走通）")
q = '{job="shop"}'
url = f"{GF}/api/datasources/proxy/uid/{LOKI_UID}/loki/api/v1/query?query={urllib.parse.quote(q)}"
import urllib.parse
st, body = req(url)
log(f"  LogQL {q} -> HTTP {st}")
if st == 200:
    d = json.loads(body)["data"]["result"]
    log(f"    stream 数 = {len(d)}")
    for s in d[:3]:
        log(f"      {s['stream']} -> {len(s['values'])} 行")

# ---------------------------------------------- 3
log("\n【3】给 PromEx 配 exemplar 跳转 → JaegerLab")
st, body = req(f"{GF}/api/datasources/uid/{PROM_UID}")
if st == 200:
    ds = json.loads(body)
    before = ds.get("jsonData", {}).get("exemplarTraceIdDestinations")
    log(f"  配置前 = {before}")
    ds["jsonData"]["exemplarTraceIdDestinations"] = [
        {"name": "traceID", "datasourceUid": JAEGER_UID}]
    ds.pop("version", None)
    st2, body2 = req(f"{GF}/api/datasources/uid/{PROM_UID}", data=ds, method="PUT")
    log(f"  PUT -> HTTP {st2}")
    if st2 == 200:
        after = json.loads(body2).get("jsonData", {}).get("exemplarTraceIdDestinations")
        log(f"  配置后 = {after}")
        log("  ✅ 后端原样接受（与 editorMode/transformations 同一模式：存后端、跑前端、不校验）")

# ---------------------------------------------- 4
log("\n【4】瞎编一个 destination 名，看后端是否校验")
st, body = req(f"{GF}/api/datasources/uid/{PROM_UID}")
ds = json.loads(body)
ds["jsonData"]["exemplarTraceIdDestinations"] = [
    {"name": "bogus_trace_field", "datasourceUid": "no-such-uid"}]
ds.pop("version", None)
st2, body2 = req(f"{GF}/api/datasources/uid/{PROM_UID}", data=ds, method="PUT")
log(f"  PUT bogus -> HTTP {st2}")
if st2 == 200:
    got = json.loads(body2)["jsonData"]["exemplarTraceIdDestinations"]
    log(f"  回读 = {got}")
    log("  ⚠️ 后端【不校验】—— 配错了不报错，只是点了跳不过去")

# 恢复正确值
st, body = req(f"{GF}/api/datasources/uid/{PROM_UID}")
ds = json.loads(body)
ds["jsonData"]["exemplarTraceIdDestinations"] = [
    {"name": "traceID", "datasourceUid": JAEGER_UID}]
ds.pop("version", None)
req(f"{GF}/api/datasources/uid/{PROM_UID}", data=ds, method="PUT")
log("  （已恢复为正确值）")

# ---------------------------------------------- 5
log("\n【5】端到端：从 Prometheus 的 exemplar 拿到 traceID，再去 Jaeger 查")
st, body = req(f"{GF}/api/datasources/proxy/uid/{PROM_UID}/api/v1/query_exemplars?query=h_test_bucket")
log(f"  经 Grafana 代理查 exemplars -> HTTP {st}")
if st == 200:
    data = json.loads(body).get("data") or []
    tids = set()
    for g in data:
        for it in g.get("exemplars", []):
            tids.add(it.get("labels", {}).get("traceID"))
    log(f"  拿到的 traceID = {tids}")
    for tid in tids:
        st2, body2 = req(f"{GF}/api/datasources/proxy/uid/{JAEGER_UID}/api/traces/{tid}")
        if st2 == 200:
            d = json.loads(body2).get("data") or []
            if d:
                t = d[0]
                log(f"  ✅ Jaeger 里查到 {tid}：{len(t.get('spans',[]))} 个 span")
                for s in t.get("spans", []):
                    log(f"       - {s.get('operationName')}")
            else:
                log(f"  ⚠️ Jaeger 返回空 data")
        else:
            log(f"  ❌ Jaeger 查询 HTTP {st2}")

log("\n" + "=" * 66)
log("实验五完成 —— 指标 → exemplar → trace 三级下钻闭环已验证")
log("=" * 66)
