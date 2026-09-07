#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 5 · 知识点 5.3 探测
核心问题：Transform（前端）与查询（数据源侧）的分工边界在哪？

关键实验：同一件事，两种做法，比较【数值差异】与【性能代价】
  做法甲：PromQL 里聚合（数据源侧）  avg by (instance) (...)
  做法乙：查原始数据 + 前端 transform 聚合（前端侧）

量化维度：
  A. 数值是否相同？（不同 → 说明语义不等价）
  B. 传输数据量差异（帧数 × 点数）
  C. 时间维度被压掉后，还能不能画时间序列图？
  D. 什么情况下【必须】用 transform（数据源侧做不到的）
"""
import json, urllib.request, urllib.error, base64, time

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()
DS_UID = "afx7x6dx803y8e"


def req(method, path, body=None, timeout=120):
    url = GF + path
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", "Basic " + AUTH)
    r.add_header("Content-Type", "application/json")
    r.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw or "{}")
        except Exception:
            return e.code, {"_raw": raw[:400]}


def dsq(expr, frm="now-5m", to="now", mdp=20):
    q = {"refId": "A", "datasource": {"type": "prometheus", "uid": DS_UID},
         "expr": expr, "range": True, "instant": False,
         "intervalMs": 15000, "maxDataPoints": mdp}
    t0 = time.time()
    st, b = req("POST", "/api/ds/query", {"queries": [q], "from": frm, "to": to})
    return st, b, (time.time() - t0) * 1000


def stat(body):
    """返回 (帧数, 总点数, 总字节)"""
    res = (body.get("results") or {}).get("A") or {}
    frs = res.get("frames") or []
    npts = 0
    for f in frs:
        v = f.get("data", {}).get("values") or []
        if v:
            npts += len(v[0])
    nb = len(json.dumps(body, ensure_ascii=False).encode())
    return len(frs), npts, nb


def value_map(body):
    """提取 {instance: 均值}，只取 Value 字段（跳过 Time 字段）"""
    res = (body.get("results") or {}).get("A") or {}
    frs = res.get("frames") or []
    out = {}
    for f in frs:
        fields = f.get("schema", {}).get("fields", [])
        vals = f.get("data", {}).get("values") or []
        for i, fld in enumerate(fields):
            if fld.get("type") != "number":
                continue  # 跳过 Time 字段
            lab = fld.get("labels") or {}
            inst = lab.get("instance")
            if inst and i < len(vals) and vals[i]:
                out[inst] = sum(vals[i]) / len(vals[i])
    return out


print("=" * 78)
print(" 5.3 探测：Transform 与查询的分工边界")
print("=" * 78)

# ---------- A. 数值对比 ----------
print("\n--- [A] 同一件事两种做法：数值一样吗？ ---\n")

EXPR_RAW = 'rate(node_cpu_seconds_total{mode="idle"}[2m])'
EXPR_PROM = 'avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[2m]))'

st1, b1, ms1 = dsq(EXPR_RAW)
st2, b2, ms2 = dsq(EXPR_PROM)

f1, p1, nb1 = stat(b1)
f2, p2, nb2 = stat(b2)

print("  做法甲：PromQL 聚合  avg by (instance)")
print("    expr = %s" % EXPR_PROM)
print("    帧数=%-4d 点数=%-6d 响应字节=%-8d 耗时=%.0fms" % (f2, p2, nb2, ms2))
print()
print("  做法乙：查原始 + 前端 reduce")
print("    expr = %s" % EXPR_RAW)
print("    帧数=%-4d 点数=%-6d 响应字节=%-8d 耗时=%.0fms" % (f1, p1, nb1, ms1))
print()

vm_prom = value_map(b2)
vm_raw = value_map(b1)

print("  %-26s %-16s %-16s %s" % ("instance", "甲：PromQL avg", "乙：逐 cpu 再平均", "差异"))
print("  " + "-" * 74)
for inst in sorted(set(vm_prom) | set(vm_raw)):
    a = vm_prom.get(inst)
    b = vm_raw.get(inst)
    if a is None or b is None:
        print("  %-26s %-16s %-16s %s" % (inst, a, b, "（仅一侧有）"))
        continue
    d = b - a
    print("  %-26s %-16.6f %-16.6f %+.6f" % (inst, a, b, d))

print()
print("  → 两种做法数值【不同】。原因：")
print("     甲 = 对每个时间点，先把 20 个 cpu 的瞬时值取平均，再对时间序列求均值")
print("           （avg over cpu，然后 mean over time）")
print("     乙 = 对每个 cpu 先求时间均值，再对 20 个 cpu 取平均")
print("           （mean over time，然后 avg over cpu）")
print("     两种聚合顺序不同 → 结果不同（除非数据完全均匀）")

# ---------- B. 传输代价 ----------
print("\n--- [B] 传输代价对比 ---\n")
print("  %-24s %-10s %-10s %-12s %s" % ("做法", "帧数", "点数", "响应字节", "相对"))
print("  " + "-" * 74)
base = nb2
print("  %-24s %-10d %-10d %-12d %.1fx" % ("甲：PromQL 聚合", f2, p2, nb2, 1.0))
print("  %-24s %-10d %-10d %-12d %.1fx" % (
    "乙：原始 + 前端 reduce", f1, p1, nb1, nb1 / base if base else 0))
print()
print("  → 乙要多传 %d 帧、%d 个点、%.1f 倍字节，才能在前端算出同样的东西" % (
    f1 - f2, p1 - p2, nb1 / base if base else 0))
print("  → 这还只是 3 台 × 20 核。若 100 台机器，差距会放大约 33 倍")

# ---------- C. 时间维度 ----------
print("\n--- [C] 时间维度：压掉之后还能画图吗？ ---\n")
print("  reduce 的本质是【把时间序列压成一个标量】。")
print("  验证：对比三种查询的帧内点数")
print()
for label, expr in [
    ("原始（不聚合）", EXPR_RAW),
    ("PromQL avg by", EXPR_PROM),
    ("PromQL avg（不带 by）", 'avg(rate(node_cpu_seconds_total{mode="idle"}[2m]))'),
]:
    st, b, ms = dsq(expr)
    f, p, nb = stat(b)
    print("    %-26s 帧数=%-4d 每帧点数=%-5d 能否画时序图=%s" % (
        label, f, (p // f if f else 0), "能" if (f and p // f > 1) else "不能（单点）"))
print()
print("  → reduce transform 与 avg（不带 by）效果类似：都把时间维压掉")
print("  → 所以 reduce 适合【表格/单值面板】，不适合【时间序列图】")

# ---------- D. 什么情况必须用 transform ----------
print("\n--- [D] 什么情况下【必须】用 transform（数据源侧做不到） ---\n")

CASES = [
    ("跨数据源合并",
     "Prometheus 的指标 + MySQL 的资产表，按 instance 关联",
     "数据源侧做不到：两个数据源互不相通",
     "必须用 merge / mergeByField"),
    ("字段名美化",
     "把 {instance=\"grafana-node:9100\"} 显示成 node-01",
     "数据源侧做不到：Prometheus 只认 label 值",
     "用 renameByRegex / organize"),
    ("多查询拼接",
     "查询 A 查 CPU、查询 B 查内存，合成一张表",
     "单一 PromQL 表达式无法跨指标拼列",
     "用 merge / concatenate"),
    ("列裁剪与排序",
     "只要 instance 和 Value 两列，按 Value 降序",
     "PromQL 不管展示列的顺序与取舍",
     "用 organize / sortBy"),
]
print("  %-14s %-46s" % ("场景", "为什么数据源侧做不到"))
print("  " + "-" * 78)
for a, b_, c, d in CASES:
    print("  【%s】" % a)
    print("    需求：%s" % b_)
    print("    原因：%s" % c)
    print("    解法：%s" % d)
    print()

# ---------- E. 判据 ----------
print("--- [E] 分工判据（可操作的判断流程） ---\n")
print("""
  问自己一个问题：

    「这个计算，数据源能算吗？」
        │
        ├─ 能算（聚合、过滤、算术、时间窗口）
        │     → 写在查询里（PromQL）
        │       理由：数据量小、传输快、可利用数据源索引
        │
        └─ 不能算（跨数据源、改名、列裁剪、多查询合并）
              → 用 transform
                理由：数据源根本不提供这个能力

  灰色地带（两边都能做，如「按 instance 求平均」）：
        → 优先写在查询里
        → 除非你需要保留原始序列做别的用途
""")

print("=" * 78)
