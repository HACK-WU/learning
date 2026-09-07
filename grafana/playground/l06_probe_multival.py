#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 6 · 6.2 探测（第一层）：= 与 =~ 的本质差异

课 3 已证：自定义变量由【前端】替换。
所以直接调 /api/ds/query 时 $host 是字面量 —— 但上一轮 [E] 出现意外：
    up{instance=~"$host"}      → 1 帧（不是 0 帧！）
    up{instance=~"$host|.*"}   → 4 帧
    rate(node_cpu_seconds_total[5m]) → 480 帧

必须查清：
  Q1. 那 1 帧里有几个点？（课 4 教训：frames=1 常常是【空帧】）
  Q2. 为什么 $host 能匹配出 1 帧？正则语义是什么？
  Q3. $host|.* 为什么是 4 帧？

关键：帧数 ≠ 数据量。本课必须【数点】而不是【数帧】。
"""
import json, urllib.request, urllib.error, base64

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()
DS_UID = "afx7x6dx803y8e"


def req(method, path, body=None, timeout=60):
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


def probe(expr, desc):
    """返回 (帧数, 总点数, 是否空帧)"""
    payload = {"queries": [{"refId": "A",
        "datasource": {"type": "prometheus", "uid": DS_UID},
        "expr": expr, "range": True, "instant": False,
        "intervalMs": 15000, "maxDataPoints": 20}],
        "from": "now-5m", "to": "now"}
    st, b = req("POST", "/api/ds/query", payload)
    res = (b.get("results") or {}).get("A") or {}
    frs = res.get("frames") or []
    npts = 0
    for f in frs:
        v = f.get("data", {}).get("values") or []
        if v:
            npts += len(v[0])
    return st, len(frs), npts, res.get("error")


print("=" * 80)
print(" 6.2 第一层探测：帧数 ≠ 数据量")
print("=" * 80)

print("\n--- [Q1] 上一轮那个 1 帧，里面有几个点？ ---\n")

CASES = [
    ('up{instance=~"$host"}', "变量未替换（API 直调）"),
    ('up{instance=~"$host|.*"}', "变量 + .* 兜底"),
    ('up{instance=~".*"}', "纯 .*（对照）"),
    ('up{instance=~"grafana-node:9100"}', "单值（模拟前端替换后）"),
    ('up{instance="grafana-node:9100"}', "单值用 = （对照）"),
]

print("  %-42s %-6s %-6s %-8s %s" % ("表达式", "帧数", "点数", "HTTP", "错误"))
print("  " + "-" * 76)
for expr, desc in CASES:
    st, nf, npts, err = probe(expr, desc)
    flag = ""
    if nf == 1 and npts == 0:
        flag = " ← 空帧！"
    print("  %-42s %-6d %-6d %-8s %s%s" % (
        expr[:42], nf, npts, st, (err[:20] if err else "无"), flag))
    print("  %-42s %s" % ("", desc))

print("\n  → 关键确认：frames=1 但 points=0 就是【空帧】")
print("     Grafana 用「1 个空 frame」表示「查到了，但没有数据」")

print("\n--- [Q2] 为什么 $host 会匹配出 1 帧？ ---\n")
print("  正则语义分析：")
print("    $host 作为正则 = 【行尾锚点 $】+ 【字面量 host】")
print("    即「以 host 结尾，且后面还有 host」——永不可能匹配")
print()
print("  那为什么是 1 帧而不是 0 帧？")
print("    因为 Prometheus 对【合法但无结果】的查询，返回一个【空 frame】")
print("    而对【语法错误】才返回 0 帧（课 4 已证）")
print()
print("  验证：对比一个语法错误的表达式")

st, nf, npts, err = probe('up{instance=~"[["}', "语法错误（对照）")
print("    语法错误表达式 → 帧数=%d 点数=%d error=%s" % (nf, npts, (err[:50] if err else "无")))

print("\n  → 两类「无数据」的区别：")
print("     语法错误     → 0 帧，带 error 字段")
print("     合法但无匹配 → 1 个空帧，无 error")

print("\n--- [Q3] $host|.* 为什么是 4 帧？ ---\n")
print("  正则 `\\$host|.*` 中的 `|` 是【或】：")
print("    分支1: `$host`   → 永不匹配")
print("    分支2: `.*`      → 匹配一切")
print("  所以整体 = 匹配一切 = 所有 up 序列")
print()
print("  这解释了课 3 那个坑：为什么有人写 `$host|.*` 能「兜底」")

st, nf, npts, err = probe('up{instance=~".*"}', "纯 .*")
print("    验证：up{instance=~\".*\"} → %d 帧 %d 点" % (nf, npts))

print("\n--- [Q4] 480 帧是什么？（多值/All 的基数问题预热）---\n")
st, nf, npts, err = probe('rate(node_cpu_seconds_total[5m])', "全量 CPU")
print("  rate(node_cpu_seconds_total[5m]) → %d 帧 %d 点" % (nf, npts))
print()
print("  分解：3 台机器 × 20 核 × ? 种 mode")
st2, b2 = req("GET", "/api/v1/label/__name__/values")
print("  查 mode 取值数：")
payload = {"queries": [{"refId": "A",
    "datasource": {"type": "prometheus", "uid": DS_UID},
    "expr": "count(count by (mode) (node_cpu_seconds_total))",
    "range": False, "instant": True, "intervalMs": 15000, "maxDataPoints": 20}],
    "from": "now-5m", "to": "now"}
st3, b3 = req("POST", "/api/ds/query", payload)
res = (b3.get("results") or {}).get("A") or {}
frs = res.get("frames") or []
if frs:
    v = frs[0].get("data", {}).get("values") or []
    if len(v) > 1 and v[1]:
        print("    mode 种类数 = %s" % v[1][0])
print("    → 3 × 20 × 8 = 480" if nf == 480 else "    → 实得 %d 帧" % nf)

print("\n" + "=" * 80)
print(" 小结：本课判据必须用【点数】，不能用【帧数】")
print("=" * 80)
