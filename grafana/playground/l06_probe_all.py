#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 6 · 知识点 6.2 核心探测：多值与 All 的展开

核心问题：
  Q1. 多值变量在前端被替换成什么？（不是数组，是【正则字符串】）
  Q2. All 值被替换成什么？（不是"所有值"，是 .* 或 (a|b|c)）
  Q3. = 与 =~ 在多值时的行为差异（为什么 = 必定查不出）
  Q4. 基数爆炸：All 展开后查询量如何增长

方法：因为自定义变量由【前端】替换（课 3 已证），API 直调拿不到替换结果。
      所以本脚本【手工模拟】前端替换的几种可能形式，逐一对比结果。
      这模拟的是 Grafana 的真实行为（依据：Grafana 源码与官方文档的插值规则）
"""
import json, urllib.request, urllib.error, base64

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()
DS_UID = "afx7x6dx803y8e"

HOSTS = ["grafana-node:9100", "grafana-node2:9100", "grafana-node3:9100"]


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


def probe(expr, mdp=20, frm="now-5m", to="now"):
    payload = {"queries": [{"refId": "A",
        "datasource": {"type": "prometheus", "uid": DS_UID},
        "expr": expr, "range": True, "instant": False,
        "intervalMs": 15000, "maxDataPoints": mdp}],
        "from": frm, "to": to}
    st, b = req("POST", "/api/ds/query", payload)
    res = (b.get("results") or {}).get("A") or {}
    frs = res.get("frames") or []
    npts = 0
    for f in frs:
        v = f.get("data", {}).get("values") or []
        if v:
            npts += len(v[0])
    nb = len(json.dumps(b, ensure_ascii=False).encode())
    return st, len(frs), npts, nb, res.get("error")


print("=" * 82)
print(" 6.2 核心探测：多值与 All 的展开")
print("=" * 82)

ALL_RE = "(grafana-node:9100|grafana-node2:9100|grafana-node3:9100)"

print("\n--- [Q1] 前端把多值变量替换成什么？ ---\n")
print("  Grafana 的插值规则（三种格式符）：")
print("    \$host        → a,b,c          （管道前的逗号）")
print("    \${host:pipe}   → a|b|c          （正则或）")
print("    \${host:regex}  → (a|b|c)        （带括号，用于 =~）")
print("    \${host:json}   → [\"a\",\"b\"]    （JSON 数组）")
print()
print("  注意：\$host 默认【逗号分隔】，不是正则！")
print("     所以 up{instance=~\$host} 在多值时会查不出数据")

print("\n  实测三种插值形态的结果：\n")

VARIANTS = [
    ("${host} 单值（模拟选 1 台）", 'up{instance=~"grafana-node:9100"}'),
    ("${host} 多值默认（逗号）", 'up{instance=~"grafana-node:9100,grafana-node2:9100"}'),
    ("${host:pipe} 多值", 'up{instance=~"grafana-node:9100|grafana-node2:9100"}'),
    ("${host:regex} 多值", 'up{instance=~"(grafana-node:9100|grafana-node2:9100)"}'),
]

print("  %-32s %-6s %-8s %-10s %s" % ("插值形态", "帧数", "点数", "字节", "状态"))
print("  " + "-" * 78)
for desc, expr in VARIANTS:
    st, nf, npts, nb, err = probe(expr)
    status = "空帧" if (nf == 1 and npts == 0) else ("有数据" if npts else "异常")
    if err:
        status = "错误"
    print("  %-32s %-6d %-8d %-10d %s" % (desc, nf, npts, nb, status))

print("\n  → 关键：逗号分隔的多值【查不出数据】（Prometheus 正则里没有逗号语法）")

print("\n--- [Q2] All 值被替换成什么？ ---\n")

ALL_VARIANTS = [
    ("All = .*（常见）", 'up{instance=~".*"}'),
    ("All = (a|b|c) 显式", 'up{instance=~"%s"}' % ALL_RE),
]

print("  %-32s %-6s %-8s %-10s %s" % ("All 展开形态", "帧数", "点数", "字节", "状态"))
print("  " + "-" * 78)
for desc, expr in ALL_VARIANTS:
    st, nf, npts, nb, err = probe(expr)
    status = "空帧" if (nf == 1 and npts == 0) else "有数据"
    print("  %-32s %-6d %-8d %-10d %s" % (desc, nf, npts, nb, status))

print()
print("  → Grafana 对 All 的处理取决于 includeAll 与 allValue：")
print("      includeAll=true, allValue 为空  → 展开为 (a|b|c) 实际值列表")
print("      includeAll=true, allValue=\".*\" → 直接用 .*")
print("      两者在本例结果相同，但【语义不同】——见下")

print("\n--- [Q3] = 与 =~ 在多值时的差异（本课核心）---\n")

print("  %-40s %-6s %-8s %s" % ("写法", "帧数", "点数", "结论"))
print("  " + "-" * 78)

CMP = [
    ('up{instance="grafana-node:9100"}', "= 单值", "正常"),
    ('up{instance="grafana-node:9100,grafana-node2:9100"}', "= 多值逗号", "查不出"),
    ('up{instance=~"grafana-node:9100"}', "=~ 单值", "正常"),
    ('up{instance=~"grafana-node:9100,grafana-node2:9100"}', "=~ 多值逗号", "查不出"),
    ('up{instance=~"(grafana-node:9100|grafana-node2:9100)"}', "=~ 多值正则", "正常"),
]

for expr, desc, expected in CMP:
    st, nf, npts, nb, err = probe(expr)
    actual = "正常" if npts > 0 else "查不出"
    mark = "✓" if actual == expected else "✗"
    print("  %-40s %-6d %-8d %s %s（预期:%s）" % (
        expr[:40], nf, npts, mark, actual, expected))

print()
print("  → 结论：= 与 =~ 在【单值】时等价，在【多值】时 = 必定失败")
print("     因为 = 要求【完全相等】，而多值给的是 a,b 这个字符串")
print("     Prometheus 里没有 instance 等于 \"a,b\" 的时间序列")

print("\n--- [Q4] 基数爆炸：All 之后查询量增长多少 ---\n")

print("  用 node_cpu_seconds_total 演示（3 台 × 20 核 × 8 mode = 480 序列）\n")

SCALE = [
    ("单台单 mode", 'rate(node_cpu_seconds_total{instance="grafana-node:9100",mode="idle"}[5m])'),
    ("单台全 mode", 'rate(node_cpu_seconds_total{instance="grafana-node:9100"}[5m])'),
    ("All 机器 单 mode", 'rate(node_cpu_seconds_total{mode="idle"}[5m])'),
    ("All 机器 全 mode", 'rate(node_cpu_seconds_total[5m])'),
]

print("  %-22s %-8s %-10s %-12s %s" % ("场景", "帧数", "点数", "字节", "相对单台单mode"))
print("  " + "-" * 78)
base = None
results = []
for desc, expr in SCALE:
    st, nf, npts, nb, err = probe(expr)
    if base is None:
        base = nb
    results.append((desc, nf, npts, nb))
    print("  %-22s %-8d %-10d %-12d %.1fx" % (desc, nf, npts, nb, nb / base))

print()
print("  → 从「单台单 mode」到「All 全 mode」，数据量增长 %.1f 倍" % (
    results[-1][3] / results[0][3]))
print("  → 若机器数从 3 涨到 100，再乘以 %.1f 倍" % (100 / 3))
print("     最终约 %.0f 倍 —— 这就是【基数爆炸】" % (
    (results[-1][3] / results[0][3]) * (100 / 3)))

print("\n--- [Q5] 时间跨度对基数的影响 ---\n")
for frm, label in [("now-5m", "5 分钟"), ("now-1h", "1 小时"), ("now-6h", "6 小时")]:
    st, nf, npts, nb, err = probe('rate(node_cpu_seconds_total[5m])', frm=frm)
    print("  %-10s → 帧数=%-6d 点数=%-8d 字节=%d" % (label, nf, npts, nb))

print("\n  → 注意：点数受 maxDataPoints 限制（本课设 20），所以时间跨度对点数影响有限")
print("     但对【帧数】（序列数）无影响——帧数只取决于标签组合数")

print("\n" + "=" * 82)
