#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 9 实验二：detected_level 的推断机制 + 时间窗对齐 + 下钻链接
"""
import json, time, urllib.request, urllib.error, urllib.parse, base64

LOKI = "http://localhost:3101"
GF = "http://localhost:3001"

def req(url, data=None, method=None):
    tok = base64.b64encode(b"admin:admin").decode()
    h = {"Authorization": f"Basic {tok}"}
    body = json.dumps(data).encode() if data is not None else None
    if body: h["Content-Type"] = "application/json"
    r = urllib.request.Request(url, data=body, headers=h, method=method)
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            return resp.status, resp.read().decode("utf-8","replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8","replace")
    except Exception as e:
        return -1, str(e)

def log(*a): print(*a, flush=True)

log("=" * 64)
log("实验二：detected_level 推断 + 时间窗对齐")
log("=" * 64)

# ---------------------------------------------------- Phase 1
log("\n【Phase 1】detected_level 是从【内容】推断的还是从【标签】抄的？")
log("  推 3 条：都有 app=probe-dl，都不带 level 标签，但内容不同")
now = int(time.time())
cases = [
    ("this line contains the word ERROR in text", "内容含 ERROR 字样"),
    ("this line contains the word DEBUG in text", "内容含 DEBUG 字样"),
    ("totally neutral sentence about weather", "中性内容"),
]
streams = []
for i, (line, _) in enumerate(cases):
    streams.append({"stream": {"app": "probe-dl"},
                    "values": [[str((now + i) * 10**9), line]]})
st, _ = req(f"{LOKI}/loki/api/v1/push", {"streams": streams})
log(f"  push -> HTTP {st}")
time.sleep(3)

end_ns = int(time.time()*10**9); start_ns = end_ns - 600*10**9
url = f"{LOKI}/loki/api/v1/query_range?query={urllib.parse.quote('{app=\"probe-dl\"}')}&start={start_ns}&end={end_ns}&limit=20"
st, body = req(url)
if st == 200:
    d = json.loads(body)["data"]["result"]
    log(f"  stream 数 = {len(d)}  ← 注意：3 条内容不同但标签相同")
    for s in d:
        lv = s["stream"].get("detected_level")
        log(f"    detected_level={lv:<10} 行数={len(s['values'])}")
        for ts, line in s["values"]:
            log(f"      {line[:60]}")

log("\n  ⚠️ 关键判断：3 条日志标签完全相同，若被分到不同 stream，")
log("     说明 detected_level 参与了 stream 划分 —— 这会【放大 stream 数】")

# ---------------------------------------------------- Phase 2
log("\n【Phase 2】时间窗对齐：同一个查询，不同时间范围")
log("  这是 9.2 的核心：指标与日志必须查【同一个时间窗】")
all_q = '{job="shop"}'
for mins, desc in [(1, "最近 1 分钟"), (5, "最近 5 分钟"), (60, "最近 60 分钟")]:
    e = int(time.time()*10**9); s = e - mins*60*10**9
    u = f"{LOKI}/loki/api/v1/query_range?query={urllib.parse.quote(all_q)}&start={s}&end={e}&limit=200"
    st, body = req(u)
    n = 0
    if st == 200:
        n = sum(len(x["values"]) for x in json.loads(body)["data"]["result"])
    log(f"  窗口 {mins:>3} 分钟 -> 命中 {n} 行   # {desc}")

log("\n  Grafana 的时间变量（下钻链接要用）：")
for v, desc in [("$__from", "窗口起始（毫秒时间戳）"),
                ("$__to", "窗口结束（毫秒时间戳）"),
                ("$__auto_interval", "自动步长"),
                ("${__from:date}", "格式化为日期")]:
    log(f"    {v:<22} {desc}")

# ---------------------------------------------------- Phase 3
log("\n【Phase 3】下钻链接的真实形态")
log("  在 Grafana 面板上加 dataLink，点一下从指标跳日志")
log("  链接模板（Loki Explore）：")
link = ("/explore?left=" + urllib.parse.quote(
    '{"datasource":"<LOKI_UID>","queries":[{"refId":"A","expr":"{job=\\"shop\\"}"}],'
    '"range":{"from":"${__from}","to":"${__to}"}}'))
log(f"    {link[:110]}...")
log("\n  ${__from} / ${__to} 会被前端替换成当前 dashboard 的时间窗 ——")
log("  这正是课 3 学过的『时间选择器是共享的』在本课的兑现")

# ---------------------------------------------------- Phase 4
log("\n【Phase 4】标签透传：从指标的标签跳到日志的标签")
log("  指标 node_load1 有 instance 标签；日志有 svc 标签")
log("  若两者【没有共同标签】，下钻就只能靠时间窗，无法精确定位")
log("  → 这就是为什么建模时要让指标与日志共享一套标签（如 service / instance）")

log("\n" + "=" * 64)
log("实验二完成")
log("=" * 64)
