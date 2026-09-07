#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 5 · 5.2 补充：merge 场景 —— 多查询如何合成一张表
这是 transform 最典型的「数据源侧做不到」的场景。

实验：
  查询 A：CPU idle 率（by instance）
  查询 B：内存可用率（by instance）
  两者是【不同的指标】，单一 PromQL 表达式无法把它们拼成两列
  → 必须用 merge transform（或 PromQL 的算术，但那是另一回事）

同时对比：
  做法甲：PromQL 里用 / 算术合并（若语义可表达）
  做法乙：两个查询 + merge transform
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


def q(ref, expr, fmt=None):
    d = {"refId": ref, "datasource": {"type": "prometheus", "uid": DS_UID},
         "expr": expr, "range": True, "instant": False,
         "intervalMs": 15000, "maxDataPoints": 20}
    if fmt:
        d["legendFormat"] = fmt
    return d


def show(body, label):
    res = body.get("results") or {}
    print("  [%s]" % label)
    for ref in sorted(res.keys()):
        r = res[ref]
        frs = r.get("frames") or []
        print("    %s: %d 帧" % (ref, len(frs)))
        for f in frs[:3]:
            fields = f.get("schema", {}).get("fields", [])
            vals = f.get("data", {}).get("values") or []
            nm = None
            for i, fl in enumerate(fields):
                if fl.get("type") == "number":
                    lab = fl.get("labels") or {}
                    v = vals[i][-1] if i < len(vals) and vals[i] else None
                    nm = "instance=%s 最后值=%s" % (
                        lab.get("instance"),
                        round(v, 6) if isinstance(v, (int, float)) else v)
            if nm:
                print("      %s" % nm)
        if len(frs) > 3:
            print("      ... 还有 %d 帧" % (len(frs) - 3))
    print()


print("=" * 76)
print(" 5.2 补充：merge 场景 —— 多查询合成一张表")
print("=" * 76)

CPU = 'avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[2m]))'
MEM = 'avg by (instance) (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)'

print("\n--- [1] 两个独立查询，各返回什么 ---\n")

st, b = req("POST", "/api/ds/query", {
    "queries": [q("A", CPU), q("B", MEM)],
    "from": "now-5m", "to": "now"})
print("  外层 HTTP %s" % st)
print("  results 的 key：%s" % ", ".join(sorted((b.get("results") or {}).keys())))
show(b, "A=CPU idle 率, B=内存可用率")

print("  → 两个查询各自独立返回，key 分别是 A 和 B")
print("  → 它们【没有】被自动合并 —— merge 需要显式配置 transform")

print("\n--- [2] 关键：merge transform 之后应该是什么样 ---\n")
print("  merge 按时间轴把两个结果并起来，字段变成：")
print("    Time | Value #A (instance=X) | Value #B (instance=X)")
print()
print("  用模拟展示合并后的表头：")
res = b.get("results") or {}
for ref in sorted(res.keys()):
    frs = res[ref].get("frames") or []
    if frs:
        f0 = frs[0]
        fields = f0.get("schema", {}).get("fields", [])
        names = [fl.get("name") for fl in fields]
        print("    %s 的字段：%s" % (ref, ", ".join(str(n) for n in names)))
print()
print("  merge 后：Time + A.Value + B.Value（三列）")
print("  再由 organize 重命名为：Time + CPU空闲率 + 内存可用率")

print("\n--- [3] 为什么这个场景【必须】用 transform ---\n")
print("  有人会问：PromQL 不能一次查出来吗？")
print()
print("  试试用算术把两个指标拼在一起：")
COMBINED = ('avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[2m]))'
            ' / avg by (instance) (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)')
st2, b2 = req("POST", "/api/ds/query", {
    "queries": [q("A", COMBINED)], "from": "now-5m", "to": "now"})
r2 = (b2.get("results") or {}).get("A") or {}
print("    表达式：%s" % COMBINED[:70] + "...")
print("    结果：%d 帧，error=%s" % (len(r2.get("frames") or []), r2.get("error", "无")))
print()
print("  → 能算，但得到的是【比值】（一个没有业务含义的数）")
print("  → 我想要的不是比值，而是【两列并排展示】")
print("  → 这是【展示形态】问题，不是【计算】问题")
print("  → 计算归数据源，形态归 transform —— 这就是 5.3 的分工")

print("\n--- [4] 小结：多查询 + merge 的典型工作流 ---\n")
print("""  1. 查询 A：查 CPU（by instance）
  2. 查询 B：查内存（by instance）
  3. Transform 1：merge        → 按时间轴并成一张宽表
  4. Transform 2：organize     → 只保留需要的列、改列名
  5. Transform 3：sortBy       → 按某列排序

  注意 transform 是【链式】执行的：
    上一个的输出 = 下一个的输入
    顺序很重要（先 merge 再 organize，反过来会出错）
""")

print("=" * 76)
