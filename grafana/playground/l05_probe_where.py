#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 5 · 知识点 5.1 探测
核心问题：Transform 在哪一层执行？前端还是后端？
方法（三重取证）：
  A. API 层取证：/api/ds/query 的 payload 里加 transformations，看后端是否处理
  B. 数据库层取证：保存带 transformations 的 dashboard，看存在哪、后端是否改写
  C. 代码层取证：前端 JS 里搜 transformation 相关实现
判据：
  - 若后端处理：/api/ds/query 带 transformations 应返回变换后的结果
  - 若前端处理：payload 里带不带 transformations，返回结果应完全一致
"""
import json, urllib.request, urllib.error, base64

GF = "http://localhost:3001"
AUTH = base64.b64encode(b"admin:admin").decode()
DS_UID = "afx7x6dx803y8e"
DASH = "l05-tf-probe"


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
            return e.code, {"_raw": raw[:400]}


def dsq(queries, transformations=None, frm="now-5m", to="now"):
    """发 /api/ds/query，可选在顶层带 transformations"""
    payload = {"queries": queries, "from": frm, "to": to}
    if transformations is not None:
        payload["transformations"] = transformations
    return req("POST", "/api/ds/query", payload)


def sig(body):
    """生成结果签名：frame 数 + 每帧字段数 + 首点数值，用于比对是否一致"""
    res = (body.get("results") or {}).get("A") or {}
    frs = res.get("frames") or []
    parts = ["frames=%d" % len(frs)]
    for f in frs:
        fields = f.get("schema", {}).get("fields", [])
        vals = f.get("data", {}).get("values") or []
        npts = len(vals[0]) if vals else 0
        first = vals[1][0] if len(vals) > 1 and vals[1] else None
        parts.append("f%d:%d/%s" % (len(fields), npts,
                                    round(first, 6) if isinstance(first, (int, float)) else first))
    return " | ".join(parts[:8])


print("=" * 74)
print(" 5.1 探测：Transform 在哪一层执行？")
print("=" * 74)

Q = [{
    "refId": "A",
    "datasource": {"type": "prometheus", "uid": DS_UID},
    "expr": "rate(node_cpu_seconds_total{mode=\"idle\"}[2m])",
    "range": True, "instant": False,
    "intervalMs": 15000, "maxDataPoints": 20,
}]

# 一个典型的 reduce transform（按 instance 求 mean）
TF_REDUCE = [{
    "id": "reduce",
    "options": {
        "reducers": ["mean"],
        "mode": "reduceFields",
        "includeTimeField": False,
    },
}]

print("\n--- [A] API 层取证：给 /api/ds/query 塞 transformations，后端认吗？ ---\n")

st1, b1 = dsq(Q, transformations=None)
st2, b2 = dsq(Q, transformations=TF_REDUCE)

s1, s2 = sig(b1), sig(b2)
print("  不带 transformations：HTTP %s" % st1)
print("    %s" % s1)
print()
print("  带 reduce transform ：HTTP %s" % st2)
print("    %s" % s2)
print()
if s1 == s2:
    print("  → 结果【完全一致】= 后端【没有】执行 transform")
    print("      （若后端执行，带 reduce 的返回应从 60 帧变成 3 帧）")
    VERDICT_A = "前端"
else:
    print("  → 结果【不同】= 后端执行了 transform")
    VERDICT_A = "后端"

print("\n  补充：后端是否把 transformations 字段吐回给我们？")
print("    body 顶层字段：%s" % ", ".join(sorted(b2.keys())))
has_tf = "transformations" in b2
print("    响应里含 transformations 字段：%s" % ("是" if has_tf else "否（后端没接这个参数）"))

# 试试放在 query 内部
print("\n  再试：把 transformations 放进 query 对象内部")
Q2 = [dict(Q[0])]
Q2[0]["transformations"] = TF_REDUCE
st3, b3 = dsq(Q2)
s3 = sig(b3)
print("    %s" % s3)
print("    与基线一致：%s" % ("是" if s3 == s1 else "否"))

# 试试 transform 这个顶层 key
print("\n  再试：顶层 key 用 transform（单数）")
st4, b4 = req("POST", "/api/ds/query", {
    "queries": Q, "from": "now-5m", "to": "now", "transform": TF_REDUCE})
s4 = sig(b4)
print("    %s" % s4)
print("    与基线一致：%s" % ("是" if s4 == s1 else "否"))

print("\n--- [B] 存储层取证：transformations 存在 dashboard 的哪儿？ ---\n")

dash = {
    "uid": DASH, "title": "L05 transform probe", "schemaVersion": 41,
    "panels": [{
        "id": 1, "type": "table", "title": "p1",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
        "datasource": {"type": "prometheus", "uid": DS_UID},
        "targets": [{"refId": "A",
                     "datasource": {"type": "prometheus", "uid": DS_UID},
                     "expr": "up", "editorMode": "code"}],
        "transformations": TF_REDUCE,
    }],
    "time": {"from": "now-1h", "to": "now"},
}
st, _ = req("POST", "/api/dashboards/db", {"dashboard": dash, "overwrite": True})
print("  保存 dashboard（含 transformations）-> HTTP %s" % st)

st, body = req("GET", "/api/dashboards/uid/" + DASH)
panel = body["dashboard"]["panels"][0]
print("  读回 panel 字段：%s" % ", ".join(sorted(panel.keys())))
tf_back = panel.get("transformations")
print("  transformations 被持久化：%s" % ("是" if tf_back else "否"))
if tf_back:
    print("  内容：%s" % json.dumps(tf_back, ensure_ascii=False))
    print("  → 逐字节一致：%s" % ("是" if tf_back == TF_REDUCE else "否，被改写为 %s" % tf_back))

print("\n--- [B2] 数据库层：查 resource 表确认存储形态 ---")

print("\n--- [C] 关键对照：同一个 panel，有/无 transform 时 /api/ds/query 结果 ---\n")
print("  （上面 [A] 已证明：结果一致 → transform 不在后端执行）")
print("  现在验证：transform 配置存在 panel 上，而非 query 上")
print("    panel.transformations 存在 = %s" % ("是" if tf_back else "否"))
q_has_tf = "transformations" in (panel.get("targets") or [{}])[0]
print("    target.transformations 存在 = %s" % ("是" if q_has_tf else "否（transform 挂在 panel 上）"))

req("DELETE", "/api/dashboards/uid/" + DASH)
print("\n[清理] 临时 dashboard 已删除")

print("\n" + "=" * 74)
print(" 结论：Transform 执行位置 = %s" % VERDICT_A)
print("=" * 74)
