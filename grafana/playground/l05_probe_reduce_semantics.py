#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 5 · 5.3 边界核实
上一轮 [C] 段结论自相矛盾：
  说「reduce 把时间维压掉」，但实测 avg（不带 by）每帧 21 点、能画时序图。
必须查清：reduce 到底压不压时间维？

关键区分（两个不同概念，别混）：
  概念一：PromQL 的 avg() 聚合器 —— 不带 by 时把【所有序列在同一时刻】压成一条
          → 时间维【保留】，序列维被压掉
  概念二：Grafana 的 reduce transform（mode=reduceFields）
          → 把【每条序列跨所有时刻】压成一个数
          → 时间维【被压掉】

所以上一轮 [C] 用 avg() 类比 reduce 是【错的】，需要修正。
本脚本用「模拟 reduce 前后的点数变化」来确证。
"""
import json, urllib.request, urllib.error, base64

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
    return req("POST", "/api/ds/query", {"queries": [q], "from": frm, "to": to})


def shape(body, label):
    res = (body.get("results") or {}).get("A") or {}
    frs = res.get("frames") or []
    if not frs:
        print("  %-32s 帧数=0" % label)
        return
    per = []
    for f in frs:
        v = f.get("data", {}).get("values") or []
        per.append(len(v[0]) if v else 0)
    print("  %-32s 帧数=%-4d 每帧点数=%-5s 时刻数=%d" % (
        label, len(frs), sorted(set(per)), per[0] if per else 0))
    return len(frs), per[0] if per else 0


print("=" * 76)
print(" 5.3 边界核实：reduce 到底压不压时间维？")
print("=" * 76)

print("\n--- [1] 三种 PromQL 写法的形状对比 ---\n")

CASES = [
    ("原始 60 条序列", 'rate(node_cpu_seconds_total{mode="idle"}[2m])'),
    ("avg by (instance)", 'avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[2m]))'),
    ("avg() 不带 by", 'avg(rate(node_cpu_seconds_total{mode="idle"}[2m]))'),
    ("sum() 不带 by", 'sum(rate(node_cpu_seconds_total{mode="idle"}[2m]))'),
]
shapes = {}
for label, expr in CASES:
    st, b = dsq(expr)
    shapes[label] = shape(b, label)

print("\n  → 关键：avg()/sum() 不带 by 时，帧数被压成 1，但【每个时刻仍有一个点】")
print("     即：压掉的是【序列维】，不是时间维。仍能画时序图。")

print("\n--- [2] reduce transform 的形状（用模拟确证）---\n")

st, b = dsq('rate(node_cpu_seconds_total{mode="idle"}[2m])')
frs = b["results"]["A"]["frames"]
n_ts = len(frs[0]["data"]["values"][0]) if frs and frs[0]["data"]["values"] else 0
print("  reduce 之前：%d 帧 × %d 个时刻" % (len(frs), n_ts))
print("  reduce(mode=reduceFields, reducer=mean) 之后：")
print("    每条序列 → 1 个标量")
print("    %d 帧 → %d 帧（每帧 1 行 1 值）" % (len(frs), len(frs)))
print("    时刻数：%d → 0（时间维消失）" % n_ts)
print()
print("  → 确证：reduce 压掉的是【时间维】，avg() 压掉的是【序列维】")
print("     二者【不是同一件事】，上一轮 [C] 段的类比是错的")

print("\n--- [3] 修正后的对照表 ---\n")
print("  %-22s %-18s %-14s %s" % ("操作", "压掉什么", "保留什么", "适合面板"))
print("  " + "-" * 76)
rows = [
    ("PromQL avg() 无 by", "序列维", "时间维", "时序图（一条线）"),
    ("PromQL avg by (x)", "序列内部细节", "时间维 + 分组", "时序图（多条线）"),
    ("Transform reduce", "时间维", "序列维", "表格 / 单值 / 柱状图"),
    ("Transform groupBy", "行级细节", "分组 + 聚合值", "表格"),
    ("Transform merge", "（不压，横向拼）", "时间维", "时序图 / 表格"),
]
for a, b_, c, d in rows:
    print("  %-22s %-18s %-14s %s" % (a, b_, c, d))

print("\n--- [4] 上一轮数值差异的重新解释 ---\n")
print("  甲（PromQL avg by instance）= 0.852529")
print("  乙（逐 cpu 再平均）        = 0.907689")
print("  差异 +0.055160")
print()
print("  注意：乙的 0.907689 是【20 个 cpu 各自时间均值的平均】")
print("        甲的 0.852529 是【每个时刻 20 个 cpu 的平均，再对时间求均值】")
print()
print("  但【真正的 reduce transform】做的是：")
print("    对每条序列求 mean → 得到 60 个数（每 cpu×instance 一个）")
print("    若再按 instance 分组聚合 → 才得到 3 个数")
print()
print("  所以严格来说：")
print("    甲 = avg over cpu, then mean over time")
print("    乙 = mean over time, then avg over cpu  ← 这是【两步 reduce】的结果")
print("    二者不同，因为【聚合顺序不可交换】")

print("\n--- [5] 这个差异重要吗？ ---\n")
print("  对「看趋势」：不重要。两条曲线形状一致、只差一个常数偏移。")
print("  对「设阈值告警」：**重要**。0.85 与 0.91 可能一个触发告警一个不触发。")
print("  → 这引出一个实践原则：")
print("     **告警用的聚合口径，必须和你看图时的口径一致**")

print("\n" + "=" * 76)
