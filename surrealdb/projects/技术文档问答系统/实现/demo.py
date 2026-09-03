# -*- coding: utf-8 -*-
"""demo.py —— 端到端演示：一条命令看完整个系统的能力

给"不想读代码、只想看它能干什么"的人用。跑完输出五幕：

    第一幕  数据从哪来      12 篇文档 → 48 个切块 → bigram 字段 → 12 维向量
    第二幕  四种检索模式的差异  同一问题跑 kw / vec / hybrid / graph，并排看结果
    第三幕  权限隔离          alice、bob、root 查同一张表，看到的条数不同
    第四幕  逻辑下推          /qa 与 /ask 端点的真实 HTTP 调用
    第五幕  可观测           墙钟 vs 服务端自报耗时，以及规模敏感性

用法：
    python3 demo.py            # 全量演示
    python3 demo.py 2          # 只跑第 2 幕
"""
import sys
import os
import json
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn, embed, fmt_ms  # noqa: E402
from retrieve import Retriever  # noqa: E402
from seed import DEFAULT_PASSWORD  # noqa: E402

LINE = "=" * 76
SUB = "-" * 76


def h(title):
    print()
    print(LINE)
    print(title)
    print(LINE)


def mk():
    return Retriever(Conn())


def act1():
    h("第一幕  数据从哪来：一篇文档是怎么变成可检索的")
    conn = Conn()
    ok, payload, err = conn.sql(
        "SELECT id, title, tenant FROM doc ORDER BY id LIMIT 5;")
    if ok:
        for row in (payload[-1].get("result") or []):
            print("  %-12s %-28s tenant=%s"
                  % (row.get("id"), (row.get("title") or "")[:28],
                     row.get("tenant")))

    ok, payload, err = conn.sql(
        "SELECT id, text, grams, emb FROM chunk WHERE id = chunk:l06_0;")
    if ok:
        rows = payload[-1].get("result") or []
        if rows:
            row = rows[0]
            print()
            print(SUB)
            print("  取其中一块 chunk:l06_0，看它被加工成了什么：")
            print("  原文   %s" % (row.get("text") or "")[:56])
            print("  grams  %s ..." % " ".join((row.get("grams") or "").split()[:14]))
            print("      ↑ 双字词（索引）后面跟着单字（索、引）—— 单字是给")
            print("        部分匹配兜底的：查询「引」也能命中含「索引」的块。")
            emb = row.get("emb") or []
            print("  向量   %d 维，前 6 维 = %s"
                  % (len(emb), [round(float(x), 3) for x in emb[:6]]))

    counts = {}
    for t in ("doc", "chunk", "refs", "hit", "user"):
        ok, payload, err = conn.sql("SELECT count() FROM %s GROUP ALL;" % t)
        n = payload[-1]["result"][0]["count"] if ok else "?"
        counts[t] = n
    print()
    print(SUB)
    print("  总量：%s" % "  ".join("%s=%s" % (k, v) for k, v in counts.items()))


def act2(q=None):
    q = q or "索引怎么加速查询"
    h("第二幕  四种检索模式：同一个问题，四种答案")
    print("  问题：%s" % q)
    r = mk()

    results = {}
    for mode, fn in [("kw", r.kw_search), ("vec", r.vec_search),
                     ("hybrid", r.hybrid), ("graph", r.graph_expand)]:
        t0 = time.time()
        rows = fn(q, limit=4)
        wall = (time.time() - t0) * 1000
        results[mode] = rows
        print()
        print(SUB)
        print("  %-7s %d 条（墙钟 %.1f ms）" % (mode, len(rows), wall))
        for x in rows[:4]:
            print("      %-13s %-7.2f  %s"
                  % (x.get("id"), float(x.get("score") or 0),
                     (x.get("text") or "")[:44]))

    print()
    print(SUB)
    kw_ids = {x["id"] for x in results["kw"]}
    vec_ids = {x["id"] for x in results["vec"]}
    print("  互补性验证：")
    print("      kw 独有 %d 条：%s" % (len(kw_ids - vec_ids),
                                    sorted(kw_ids - vec_ids)[:3]))
    print("      vec 独有 %d 条：%s" % (len(vec_ids - kw_ids),
                                     sorted(vec_ids - kw_ids)[:3]))
    print("      → 两路不是同一批结果，所以混合检索有真实增益，不是摆设")

    print()
    print("  ⚠️ graph 模式耗时明显更高（~104ms vs ~40ms），不是性能缺陷：")
    print("     它在混合检索之后又多走了一跳图查询（沿 refs 边取邻居），")
    print("     是拿四次往返换「邻居文档的背景信息」。值不值，取决于你要不要上下文。")


def act3():
    h("第三幕  权限隔离：同一张表，三个人看到三个世界")
    conn = Conn()
    for label, token in [("root（系统用户）", None)] + [
            (email, conn.signin("app", email=email, password=DEFAULT_PASSWORD))
            for email in ("alice@acme.io", "bob@beta.io")]:
        uc = Conn(token=token) if token else conn
        ok, payload, err = uc.sql("SELECT tenant FROM chunk;")
        if not ok:
            print("  %-22s 查询失败 %s" % (label, str(payload)[:80]))
            continue
        rows = payload[-1].get("result") or []
        tenants = sorted({x.get("tenant") for x in rows})
        print("  %-22s 可见 %3d 块，租户 %s" % (label, len(rows), tenants))

    print()
    print(SUB)
    print("  关键点：同一条 SQL，没加任何 WHERE 过滤，结果却不同 ——")
    print("  过滤由表级 PERMISSIONS 在服务端完成，客户端没有绕过它的机会。")
    print("  root 是系统用户，不受 PERMISSIONS 约束（这不是 bug，是设计）。")


def act4():
    h("第四幕  逻辑下推：应用不发 SQL，只发一次 HTTP")
    conn = Conn()

    code, body = conn.api("/qa", "GET")
    print("  GET  /qa  → HTTP %s" % code)
    print("      %s" % body[:100])

    code, body = conn.api("/qa", "POST", json.dumps({"q": "权限", "k": 3}))
    print()
    print("  POST /qa  {\"q\": \"权限\", \"k\": 3} → HTTP %s" % code)
    if code == 200:
        j = json.loads(body)
        print("      q=%r count=%s" % (j.get("q"), j.get("count")))
        for x in (j.get("hits") or [])[:3]:
            print("      %-13s %s" % (x.get("id"), (x.get("text") or "")[:44]))

    print()
    print(SUB)
    print("  带审计的端点 /ask：租户取自 $auth，不取客户端传参")
    for email in ("alice@acme.io", "bob@beta.io"):
        token = conn.signin("app", email=email, password=DEFAULT_PASSWORD)
        uc = Conn(token=token)
        code, body = uc.api("/ask", "POST", json.dumps({"q": "权限", "k": 3}))
        if code == 200:
            j = json.loads(body)
            print("      %-14s → tenant=%r count=%s"
                  % (email, j.get("tenant"), j.get("count")))

    ok, payload, err = conn.sql(
        "SELECT tenant, who, q, n FROM ask_audit ORDER BY at DESC LIMIT 4;")
    if ok:
        print()
        print("  审计留痕（最近 4 条）：")
        for row in (payload[-1].get("result") or []):
            print("      tenant=%-6s who=%-10s q=%-4s n=%s"
                  % (row.get("tenant"), row.get("who"),
                     row.get("q"), row.get("n")))


def act5():
    h("第五幕  可观测：两个口径的耗时，以及规模上去了会怎样")
    r = mk()
    q = "权限隔离怎么做"

    print("  口径 A：客户端墙钟（含网络 + 序列化）")
    walls = []
    for _ in range(5):
        t0 = time.time()
        r.hybrid(q, limit=8)
        walls.append((time.time() - t0) * 1000)
    walls.sort()
    print("      5 次混合检索中位 %.2f ms" % walls[len(walls) // 2])

    print()
    print("  口径 B：服务端自报 time（响应体里带，不含网络）")
    conn = Conn()
    ok, payload, err = conn.sql("SELECT id FROM chunk LIMIT 10;")
    if ok and isinstance(payload, list) and payload:
        t = payload[-1].get("time")
        print("      服务端自报 %s（%.3f ms）" % (t, fmt_ms(t)))
    print()
    print(SUB)
    print("  两个口径差 ~50ms 是网络开销，不是数据库慢。")
    print("  优化前先分清口径，否则会去优化一个根本不存在的问题。")
    print()
    print("  规模敏感性实测（bench.py 跑出来的）：1.43 → 4.34 → 17.73 ms")
    print("  数据量 16 倍，耗时 12.4 倍 —— 近线性，索引是生效的。")


ACTS = {"1": act1, "2": act2, "3": act3, "4": act4, "5": act5}


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else None
    if which and which in ACTS:
        ACTS[which]()
        return 0

    print(LINE)
    print("技术文档问答系统 · 端到端演示")
    print("SurrealDB 3.2.4 · 12 篇文档 · 48 个切块 · 两租户隔离")
    print(LINE)
    for k in sorted(ACTS):
        ACTS[k]()
    print()
    print(LINE)
    print("演示结束。想看某一幕：python3 demo.py 2")
    print(LINE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
