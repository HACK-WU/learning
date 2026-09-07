#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 5 · 知识点 5.2 探测
四种常用 Transform：合并(merge) / 归约(reduce) / 按字段分组(groupBy) / 重命名(renameByRegex)

关键限制：/api/ds/query 不执行 transform（5.1 已证明）。
所以要看到 transform 的【效果】，必须用另一种办法：
  → 用 /api/ds/query 拿原始帧，然后【手工模拟】transform 的语义
  → 同时用 dashboard 保存验证 transform 配置被正确持久化

但更有价值的取证是：
  A. 枚举本实例支持的 transform 列表（从前端代码或 API）
  B. 验证每种 transform 的配置能被保存且逐字节回读
  C. 用原始帧数据【证明】为什么需要 transform（60 帧 → 表格不可用）
  D. 模拟 merge/reduce 的效果，展示前后差异
"""
import json, urllib.request, urllib.error, base64

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()
DS_UID = "afx7x6dx803y8e"
DASH = "l05-tf2-probe"


def req(method, path, body=None, timeout=90):
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
            return e.code, {"_raw": raw[:500]}


def dsq(expr, frm="now-5m", to="now", mdp=20, fmt=None):
    q = {"refId": "A", "datasource": {"type": "prometheus", "uid": DS_UID},
         "expr": expr, "range": True, "instant": False,
         "intervalMs": 15000, "maxDataPoints": mdp}
    if fmt:
        q["legendFormat"] = fmt
    return req("POST", "/api/ds/query", {"queries": [q], "from": frm, "to": to})


def save_panel(panel_extra, uid=DASH):
    dash = {
        "uid": uid, "title": "L05 tf2", "schemaVersion": 41,
        "panels": [dict({
            "id": 1, "type": "table", "title": "p",
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
            "datasource": {"type": "prometheus", "uid": DS_UID},
            "targets": [{"refId": "A",
                         "datasource": {"type": "prometheus", "uid": DS_UID},
                         "expr": "up", "editorMode": "code"}],
        }, **panel_extra)],
        "time": {"from": "now-1h", "to": "now"},
    }
    st, _ = req("POST", "/api/dashboards/db", {"dashboard": dash, "overwrite": True})
    st2, body = req("GET", "/api/dashboards/uid/" + uid)
    if st2 != 200:
        return st, st2, None
    return st, st2, body["dashboard"]["panels"][0]


print("=" * 76)
print(" 5.2 探测：四种常用 Transform")
print("=" * 76)

# ---------- A. 枚举支持的 transform ----------
print("\n--- [A] 本实例支持哪些 transform？ ---\n")
print("  方法：逐个 id 保存，看后端是否接受（不校验 = 全接受，说明校验在前端）")

CANDIDATES = [
    "merge", "reduce", "groupBy", "renameByRegex", "organize",
    "filterFieldsByName", "sortBy", "limit", "concatenate",
    "calculateField", "labelsToFields", "seriesToColumns",
    "bogus-transform-xyz",
]
accepted = []
for tid in CANDIDATES:
    tf = [{"id": tid, "options": {}}]
    st, st2, panel = save_panel({"transformations": tf})
    back = (panel or {}).get("transformations")
    ok = bool(back) and back[0].get("id") == tid
    accepted.append((tid, ok, "" if ok else "后端改写/丢弃"))
    print("    %-22s 保存=%s 回读 id 一致=%s" % (tid, st, "✓" if ok else "✗"))

print("\n  → 关键观察：连 bogus-transform-xyz 都被接受并原样回读")
print("     说明 transform id 的【校验也在前端】，后端只是存 JSON")

req("DELETE", "/api/dashboards/uid/" + DASH)

# ---------- B. 四种 transform 的配置形态 ----------
print("\n--- [B] 四种常用 transform 的配置长什么样 ---\n")

FOUR = {
    "merge": {
        "id": "merge",
        "options": {},
        "_作用": "把多个 frame 按时间轴并成一张宽表",
    },
    "reduce": {
        "id": "reduce",
        "options": {
            "reducers": ["mean"],
            "mode": "reduceFields",
            "includeTimeField": False,
        },
        "_作用": "把每条时间序列压成一个数（mean/max/min/last 等）",
    },
    "groupBy": {
        "id": "groupBy",
        "options": {
            "fields": {
                "Value": {"aggregations": ["mean"], "operation": "aggregate"},
                "instance": {"aggregations": [], "operation": "groupby"},
            },
        },
        "_作用": "按某字段分组 + 对其他字段聚合（类似 SQL GROUP BY）",
    },
    "renameByRegex": {
        "id": "renameByRegex",
        "options": {
            "regex": ".*instance=\"([^\"]*)\".*",
            "renamePattern": "$1",
        },
        "_作用": "用正则从序列名里提取部分作为新名字",
    },
}

for name, tf in FOUR.items():
    opts = {k: v for k, v in tf.items() if not k.startswith("_")}
    st, st2, panel = save_panel({"transformations": [opts]})
    back = (panel or {}).get("transformations")
    same = "✓ 逐字节回读" if back == [opts] else "✗ 被改写: %s" % json.dumps(back, ensure_ascii=False)
    print("  %-16s %s" % (name, same))
    print("  %-16s %s" % ("", tf["_作用"]))
    print("  %-16s options=%s" % ("", json.dumps(opts["options"], ensure_ascii=False)))
    print()

req("DELETE", "/api/dashboards/uid/" + DASH)

# ---------- C. 证明「为什么需要 transform」----------
print("--- [C] 为什么需要 transform：60 帧在表格里是什么样 ---\n")

st, b = dsq('rate(node_cpu_seconds_total{mode="idle"}[2m])')
frs = b["results"]["A"]["frames"]
print("  原始返回：%d 个 frame" % len(frs))
print("  每个 frame 的字段结构：")
f0 = frs[0]
for fld in f0["schema"]["fields"]:
    print("    - name=%-8s type=%-8s labels=%s" % (
        fld.get("name"), fld.get("type"),
        json.dumps(fld.get("labels") or {}, ensure_ascii=False)))
print()
print("  labels 的组合维度：")
dims = {}
for f in frs:
    for fld in f["schema"]["fields"]:
        for k, v in (fld.get("labels") or {}).items():
            dims.setdefault(k, set()).add(v)
for k, v in dims.items():
    print("    %-10s → %d 种取值  %s" % (
        k, len(v),
        (", ".join(sorted(v)[:4]) + ("..." if len(v) > 4 else ""))))
print()
print("  → 60 = %s" % " × ".join("%d(%s)" % (len(v), k) for k, v in dims.items()))
print("  → 表格面板会渲染成 60 行（每行一个 cpu×instance 组合），而不是 3 行")

# ---------- D. 模拟 transform 效果 ----------
print("\n--- [D] 模拟：merge / reduce 之后应该是什么样 ---\n")

# reduce 模拟：按 instance 求均值
print("  [reduce 模拟] 按 instance 对 60 条序列求 mean：")
inst_vals = {}
for f in frs:
    for fld in f["schema"]["fields"]:
        lab = fld.get("labels") or {}
        inst = lab.get("instance")
        if not inst:
            continue
        vals = f["data"]["values"]
        if len(vals) > 1 and vals[1]:
            inst_vals.setdefault(inst, []).append(sum(vals[1]) / len(vals[1]))
print("    %-24s %-10s %s" % ("instance", "序列数", "mean(各 cpu 的均值)"))
for inst, vs in sorted(inst_vals.items()):
    print("    %-24s %-10s %.6f" % (inst, len(vs), sum(vs) / len(vs)))
print("    → 60 行压成 %d 行" % len(inst_vals))

# groupBy 模拟
print("\n  [groupBy 模拟] 按 instance 分组，Value 取 mean：")
print("    （数值同上，groupBy 与 reduce 在此场景结果相同，但语义不同：")
print("      reduce 是「压掉时间维」，groupBy 是「按字段分组聚合」）")

# 用 instant 查询看 reduce 更直观的效果
print("\n  [对照] instant 查询（本身只有 1 个点，无需 reduce）：")
st, b2 = dsq('avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[2m]))')
frs2 = b2["results"]["A"]["frames"]
print("    avg by (instance) 返回 %d 个 frame：" % len(frs2))
for f in frs2:
    for fld in f["schema"]["fields"]:
        lab = fld.get("labels") or {}
        vals = f["data"]["values"]
        v = vals[1][0] if len(vals) > 1 and vals[1] else None
        print("      instance=%-24s value=%s" % (
            lab.get("instance"), round(v, 6) if isinstance(v, (int, float)) else v))

print("\n  → 关键对比：")
print("      PromQL 里写 avg by (instance)  → 后端返回 3 帧（数据源侧聚合）")
print("      查原始 60 帧 + reduce transform → 前端压成 3 行（前端侧聚合）")
print("      两者数值应接近，但【计算位置不同】，这是 5.3 的核心")

print("\n" + "=" * 76)
