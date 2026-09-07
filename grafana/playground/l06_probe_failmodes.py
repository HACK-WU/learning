#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 6 · 6.2 补充：三种失败模式的区分

背景：上一轮探测发现一个重要修正——
  课 4 说「语法错 → 0 帧」，但本课实测语法错也是 1 帧（空帧）。
  区别在 error 字段，不在帧数。

本脚本系统梳理「查不出数据」的几种形态，给出可操作的判据：
  F1. 静默无数据（合法但无匹配）  → 1 空帧，无 error
  F2. 语法错误                   → 1 空帧，有 error（bad_data）
  F3. 变量未替换                 → 1 空帧，无 error（伪装成 F1！）
  F4. 后端不可达                 → 0 帧，有 error（502）
  F5. 查询超时                   → 需单独构造

关键判据表：
  看【帧数】+【error 字段】+【HTTP 状态码】三者组合，而不是只看某一个
"""
import json, urllib.request, urllib.error, base64, time

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()
DS_UID = "afx7x6dx803y8e"
BAD_UID = "nonexistent-datasource-uid"


def req(method, path, body=None, timeout=30):
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
            return e.code, {"_raw": raw[:300]}
    except Exception as e:
        return -1, {"_err": str(e)[:200]}


def probe(expr, uid=DS_UID, mdp=20, timeout=30):
    payload = {"queries": [{"refId": "A",
        "datasource": {"type": "prometheus", "uid": uid},
        "expr": expr, "range": True, "instant": False,
        "intervalMs": 15000, "maxDataPoints": mdp}],
        "from": "now-5m", "to": "now"}
    t0 = time.time()
    st, b = req("POST", "/api/ds/query", payload, timeout=timeout)
    ms = (time.time() - t0) * 1000
    res = (b.get("results") or {}).get("A") or {}
    frs = res.get("frames") or []
    npts = 0
    for f in frs:
        v = f.get("data", {}).get("values") or []
        if v:
            npts += len(v[0])
    err = res.get("error")
    return st, len(frs), npts, err, ms


print("=" * 84)
print(" 6.2 补充：三种失败模式怎么区分")
print("=" * 84)

CASES = [
    ("F1 静默无数据",
     'up{instance="no-such-host:9999"}', DS_UID,
     "合法表达式，但标签值不存在"),
    ("F2 语法错误",
     'up{instance=~"[["}', DS_UID,
     "正则不合法"),
    ("F3 变量未替换",
     'up{instance=~"$host"}', DS_UID,
     "API 直调时变量是字面量"),
    ("F4 数据源不存在",
     'up', BAD_UID,
     "引用了不存在的 datasource uid"),
    ("F0 正常（对照）",
     'up{instance=~".*"}', DS_UID,
     "基准"),
]

print("\n  %-16s %-6s %-6s %-8s %-10s %s" % (
    "模式", "HTTP", "帧数", "点数", "耗时ms", "error 摘要"))
print("  " + "-" * 80)

rows = []
for label, expr, uid, desc in CASES:
    st, nf, npts, err, ms = probe(expr, uid)
    rows.append((label, st, nf, npts, err, ms))
    es = (err[:34] + "...") if err and len(err) > 34 else (err or "无")
    print("  %-16s %-6s %-6d %-6d %-8.0f %s" % (label, st, nf, npts, ms, es))
    print("  %-16s └─ %s" % ("", desc))

print("\n--- [判据表] 怎么区分这三种失败 ---\n")

print("  %-18s %-8s %-8s %-10s %s" % ("失败类型", "HTTP", "帧数", "error", "面板表现"))
print("  " + "-" * 80)
print("  %-18s %-8s %-8s %-10s %s" % ("F1 静默无数据", "200", "1（空）", "无", "空白图，不报错"))
print("  %-18s %-8s %-8s %-10s %s" % ("F2 语法错误", "200", "1（空）", "bad_data", "面板报错框"))
print("  %-18s %-8s %-8s %-10s %s" % ("F3 变量未替换", "200", "1（空）", "无", "空白图，不报错"))
print("  %-18s %-8s %-8s %-10s %s" % ("F4 数据源不存在", "400", "0", "502/404", "面板报错框"))

print()
print("  → 关键洞察：")
print("     F1 与 F3 【表现完全一样】（都是 1 空帧无 error）")
print("     都是【空白图不报错】——这是最难排查的一种")
print()
print("     F2 与 F1 的区别【不在帧数，在 error 字段】")
print("     这修正了课 4 的一个说法：课 4 说语法错是 0 帧，")
print("     本课实测是 1 个空帧 —— 区别在 error 字段有 bad_data")
print()
print("     F4 才是真正的 0 帧 + HTTP 400（外层）+ 内层 502")

print("\n--- [深挖] F1 与 F3 怎么区分？ ---\n")
print("  既然两者 API 表现一样，只能从【表达式本身】判断：")
print()
print("  方法：看 expr 里是否含有未替换的 \$ 符号")
print()

TESTS = [
    ('up{instance=~"$host"}', "含 $ → 疑似未替换"),
    ('up{instance="no-such-host:9999"}', "不含 $ → 是真的没匹配上"),
    ('up{instance=~"$host|.*"}', "含 $ 但有 .* 兜底 → 有数据"),
]
for expr, note in TESTS:
    st, nf, npts, err, ms = probe(expr)
    has_dollar = "$" in expr
    print("    %-36s 帧=%d 点=%-4d %s" % (expr[:36], nf, npts, note))

print()
print("  → 实用排查口诀：")
print("     【图上没数据 → 先看表达式里有没有没被替换的 \$】")

print("\n--- [补充] 空帧 vs 0 帧的语义 ---\n")
print("  再确认一次（课 4 与本课的差异点）：")
print()
for label, expr, uid in [
    ("合法无匹配", 'up{instance="no-such-host:9999"}', DS_UID),
    ("语法错误", 'up{instance=~"[["}', DS_UID),
    ("数据源不存在", 'up', BAD_UID),
]:
    payload = {"queries": [{"refId": "A",
        "datasource": {"type": "prometheus", "uid": uid},
        "expr": expr, "range": True, "instant": False,
        "intervalMs": 15000, "maxDataPoints": 20}],
        "from": "now-5m", "to": "now"}
    st, b = req("POST", "/api/ds/query", payload)
    res = (b.get("results") or {}).get("A") or {}
    frs = res.get("frames") or []
    err = res.get("error")
    # 检查 frame 内部结构
    if frs:
        f0 = frs[0]
        nf_fields = len(f0.get("schema", {}).get("fields", []))
        nvals = len((f0.get("data", {}).get("values") or [[]])[0])
    else:
        nf_fields, nvals = 0, 0
    print("    %-14s 帧=%d 字段数=%d 点数=%d error=%s" % (
        label, len(frs), nf_fields, nvals, (err[:40] if err else "无")))

print()
print("  → 空帧有【字段结构】但【无数据行】；0 帧是【连结构都没有】")

print("\n" + "=" * 84)
