#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 9 实验一：Loki 标签模型 + LogQL 两种查询
核心命题：Loki 只索引【标签】，不索引【日志内容】
对照：Prometheus 索引的是【指标名 + 标签】，值是数字
"""
import json, time, urllib.request, urllib.error

LOKI = "http://localhost:3101"
BASE = "http://localhost:3001"
AUTH = ("admin", "admin")

def req(url, data=None, headers=None, method=None):
    """统一 HTTP，带 basic auth"""
    if AUTH:
        import base64
        tok = base64.b64encode(f"{AUTH[0]}:{AUTH[1]}".encode()).decode()
        headers = headers or {}
        headers = dict(headers)
        headers["Authorization"] = f"Basic {tok}"
    body = json.dumps(data).encode() if data is not None else None
    if body:
        headers = headers or {}
        headers["Content-Type"] = "application/json"
    r = urllib.request.Request(url, data=body, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:
        return -1, str(e)

def log(*a):
    print(*a, flush=True)

log("=" * 62)
log("实验一：Loki 标签模型与 LogQL")
log("=" * 62)

# ---------------------------------------------------------------- Phase 0
log("\n【Phase 0】Loki 就绪状态")
st, body = req(f"{LOKI}/ready")
log(f"  GET /ready -> HTTP {st}  body={body.strip()[:60]}")
st, body = req(f"{LOKI}/loki/api/v1/labels")
labels = json.loads(body).get("data", []) if st == 200 else []
log(f"  GET /loki/api/v1/labels -> HTTP {st}, 标签键 = {labels if labels else '（空，尚无数据）'}")

# ---------------------------------------------------------------- Phase 1
log("\n【Phase 1】写入日志：验证 Loki 的推模型")
log("  Loki 不主动抓，必须由 agent（promtail / fluentd / otelcol）推给它")
log("  推的入口：POST /loki/api/v1/push")
log("  一个 stream = 一组【完全相同】的标签 + 一串 [时间戳, 行]")

now = int(time.time())
# 关键设计：3 个 stream，标签不同 —— 用来讲"标签决定 stream 数"
streams = [
    {"stream": {"job": "shop", "level": "error", "svc": "payment"},
     "values": [[str((now - 30) * 10**9), "payment failed order=1001 user=u7"],
                [str((now - 20) * 10**9), "payment timeout order=1002 user=u8"]]},
    {"stream": {"job": "shop", "level": "info", "svc": "payment"},
     "values": [[str((now - 25) * 10**9), "payment ok order=1003 user=u9"]]},
    {"stream": {"job": "shop", "level": "error", "svc": "checkout"},
     "values": [[str((now - 10) * 10**9), "checkout failed cart=c55 user=u7"]]},
]
payload = {"streams": streams}
st, body = req(f"{LOKI}/loki/api/v1/push", data=payload)
log(f"  POST /loki/api/v1/push -> HTTP {st}（204 才是成功；Loki 推成功【不返回 body】）")
log(f"  body = {body.strip()[:80]!r}")

time.sleep(3)

# ---------------------------------------------------------------- Phase 2
log("\n【Phase 2】Loki 索引了什么？—— 标签键与取值")
for ep in ["/loki/api/v1/labels", "/loki/api/v1/label/job/values",
           "/loki/api/v1/label/level/values", "/loki/api/v1/label/svc/values"]:
    st, body = req(f"{LOKI}{ep}")
    if st == 200:
        d = json.loads(body).get("data", [])
        log(f"  {ep:<45} -> {d}")
    else:
        log(f"  {ep:<45} -> HTTP {st}")

# ---------------------------------------------------------------- Phase 3
log("\n【Phase 3】LogQL 两种查询：日志查询 vs 指标查询")
log("  LogQL = Log Query Language，两种形态：")
log("    ① 日志查询（log query）  -> 返回【日志行】")
log("    ② 指标查询（metric query）-> 返回【数字】，在日志查询外面套聚合函数")

end_ns = int(time.time() * 10**9)
start_ns = (now - 120) * 10**9

def q_range(query, tag=""):
    url = (f"{LOKI}/loki/api/v1/query_range?query={urllib.parse.quote(query)}"
           f"&start={start_ns}&end={end_ns}&limit=50")
    st, body = req(url)
    return st, body

import urllib.parse
qs = [
    ('{job="shop"}', "纯标签匹配：不过滤内容"),
    ('{job="shop",level="error"}', "多标签交集"),
    ('{job="shop"} |= "failed"', "加行过滤 |=（内容包含）"),
    ('{job="shop"} |~ "order=100[12]"', "正则过滤 |~"),
    ('{job="shop"} != "ok"', "排除 !="),
]
for q, desc in qs:
    st, body = q_range(q)
    if st == 200:
        d = json.loads(body)["data"]["result"]
        n = sum(len(s["values"]) for s in d)
        log(f"  [{st}] {q:<38} streams={len(d):<2} 行数={n:<3}  # {desc}")
    else:
        log(f"  [{st}] {q:<38} 失败 # {desc}")

log("\n  ---- 指标查询（把日志变成数字）----")
metric_qs = [
    ('count_over_time({job="shop"}[2m])', "区间计数"),
    ('count_over_time({job="shop",level="error"}[2m])', "带标签的区间计数"),
    ('sum by (svc) (count_over_time({job="shop"}[2m]))', "按 svc 分组聚合"),
    ('rate({job="shop"}[2m])', "每秒速率"),
]
for q, desc in metric_qs:
    st, body = q_range(q)
    if st == 200:
        d = json.loads(body)["data"]
        rtype = d.get("resultType")
        res = d.get("result", [])
        if rtype == "vector":
            vals = [(x["metric"].get("svc", "-"), x["value"][1]) for x in res]
        else:
            vals = [(x["metric"].get("svc", "-"), len(x.get("values", []))) for x in res]
        log(f"  [{st}] resultType={rtype:<8} {q:<48} -> {vals}  # {desc}")
    else:
        log(f"  [{st}] {q:<48} 失败: {body[:100]}  # {desc}")

# ---------------------------------------------------------------- Phase 4
log("\n【Phase 4】核心对照：Loki 索引标签不索引内容")
log("  命题：查询【标签】走索引（快），查询【内容】必须全量扫（慢）")
log("  验证方式：查一个不存在的标签值 vs 查一个不存在的关键词")

import time as _t
def timed(q):
    t0 = _t.time()
    st, body = q_range(q)
    dt = (_t.time() - t0) * 1000
    n = 0
    if st == 200:
        n = sum(len(s["values"]) for s in json.loads(body)["data"]["result"])
    return st, n, dt

for q, desc in [
    ('{job="no_such_job"}', "标签不存在（走索引，直接判定无 stream）"),
    ('{job="shop"} |= "zzz_no_such_text"', "内容不存在（必须扫全部行）"),
]:
    st, n, dt = timed(q)
    log(f"  [{st}] 命中 {n} 行, 耗时 {dt:.1f}ms  # {desc}")

log("\n  两个查询都返回 0 行——但对 Loki 而言成本不同：")
log("    标签查询：查索引，未命中即返回，不碰数据块")
log("    内容查询：定位到 stream 后，逐行解压 + 字符串匹配")
log("  ⚠️ 本环境数据量太小（3 行），耗时差异不可测，此处只讲原理不编数字")

log("\n" + "=" * 62)
log("实验一完成")
log("=" * 62)
