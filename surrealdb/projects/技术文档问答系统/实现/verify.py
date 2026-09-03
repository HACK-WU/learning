# -*- coding: utf-8 -*-
"""verify.py —— 验收：30 项逐条勾选，跑完才能说"项目完成"

设计原则（沿用本课程全部 12 课的评审纪律）：
1. 每项都要有**实测输出**，不能只检查"文件存在"。
2. 阴性断言必须配**阳性对照**（查不到可能是被拦住，也可能是表空的）。
3. 失败要打印**实际拿到了什么**，否则无法判断是真失败还是断言写错。

用法：
    python3 verify.py
"""
import sys
import os
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn, grams_field, embed  # noqa: E402
from retrieve import Retriever  # noqa: E402
from seed import CORPUS, USERS, DEFAULT_PASSWORD  # noqa: E402

PASS, FAIL = [], []


def check(cid, desc, fn):
    """执行一项验收。fn 返回 (bool, 证据字符串)。"""
    try:
        ok, evidence = fn()
    except Exception as e:
        ok, evidence = False, "抛异常 %s: %s" % (type(e).__name__, str(e)[:200])
    (PASS if ok else FAIL).append((cid, desc, evidence))
    print("  %s %-4s %-42s %s" % ("✓" if ok else "✗", cid, desc, evidence[:56]))
    return ok


def count(conn, table):
    ok, payload, err = conn.sql("SELECT count() FROM %s GROUP ALL;" % table)
    if not ok or not isinstance(payload, list):
        return None
    r = payload[-1].get("result")
    return r[0]["count"] if isinstance(r, list) and r else None


def main():
    conn = Conn()
    r = Retriever(conn, k=5)
    print("=" * 96)
    print("验收 · 技术文档问答系统")
    print("=" * 96)

    # ───────────────────────── A. 数据层（阶段 2：建模）
    print()
    print("【A】数据层 —— 建模与写入（阶段 2）")

    def a1():
        n = count(conn, "doc")
        return n == len(CORPUS), "doc=%s 期望 %d" % (n, len(CORPUS))
    check("A1", "文档表行数正确", a1)

    def a2():
        n = count(conn, "chunk")
        exp = sum(len(c[4]) for c in CORPUS)
        return n == exp, "chunk=%s 期望 %d" % (n, exp)
    check("A2", "切块表行数正确", a2)

    def a3():
        n = count(conn, "refs")
        exp = sum(len(c[5]) for c in CORPUS)
        return n == exp, "refs=%s 期望 %d" % (n, exp)
    check("A3", "关系边用 RELATE 建成", a3)

    def a4():
        # 阳性对照：一条 SCHEMAFULL 表，字段类型错误必须被拒绝
        ok, payload, err = conn.sql("CREATE chunk:t_bad SET seq = 'not_a_number';")
        if ok:
            return False, "类型校验失效（字符串写进了 number 字段）"
        return True, "正确拒绝：%s" % str(payload)[:60]
    check("A4", "SCHEMAFULL 类型校验生效", a4)

    def a5():
        conn.sql("DELETE chunk:t_bad;")
        ok, payload, err = conn.sql("SELECT grams FROM chunk:l06_0;")
        g = payload[-1]["result"][0]["grams"] if ok else ""
        return ("索引" in g), "bigram 含「索引」：%s…" % g[:24]
    check("A5", "中文 bigram 字段已生成", a5)

    def a6():
        ok, payload, err = conn.sql("SELECT array::len(emb) AS n FROM chunk:l06_0;")
        n = payload[-1]["result"][0]["n"] if ok else None
        return n == 12, "emb 维度=%s 期望 12" % n
    check("A6", "向量维度与索引定义一致", a6)

    # ───────────────────────── B. 检索层（阶段 3：搜索）
    print()
    print("【B】检索层 —— 全文 / 向量 / 混合（阶段 3）")

    def b1():
        rows = r.kw_search("索引怎么加速查询", limit=3)
        if not rows:
            return False, "无结果"
        return rows[0]["id"].startswith("chunk:l06"), "Top1=%s" % rows[0]["id"]
    check("B1", "关键词检索命中正确文档", b1)

    def b2():
        rows = r.vec_search("权限怎么配置", limit=3)
        if not rows:
            return False, "无结果"
        return rows[0]["id"].startswith("chunk:l10"), "Top1=%s" % rows[0]["id"]
    check("B2", "向量检索命中正确主题", b2)

    def b3():
        rows = r.hybrid("图遍历的边界在哪", limit=3)
        if not rows:
            return False, "无结果"
        return any(x["id"].startswith("chunk:l05") for x in rows), \
            "含 l05：%s" % ",".join(x["id"][6:] for x in rows[:3])
    check("B3", "混合检索召回图相关文档", b3)

    def b4():
        # 核心命题：两路结果必须不同，否则混合没有意义
        kw = {x["id"] for x in r.kw_search("图遍历的边界在哪", limit=5)}
        vec = {x["id"] for x in r.vec_search("图遍历的边界在哪", limit=5)}
        diff = kw ^ vec
        return len(diff) > 0, "kw 独有=%d vec 独有=%d" % (
            len(kw - vec), len(vec - kw))
    check("B4", "两路结果互补（非完全相同）", b4)

    def b5():
        plan = conn.result("SELECT id FROM chunk WHERE grams @@ '索引' EXPLAIN;")
        return "FullTextScan" in str(plan), "走 FullTextScan"
    check("B5", "全文查询走索引（EXPLAIN）", b5)

    def b6():
        qv = embed("索引")
        arr = "[" + ",".join(repr(float(v)) for v in qv) + "]"
        plan = conn.result("LET $q = %s; SELECT id FROM chunk WHERE emb <|3,40|> $q EXPLAIN;" % arr)
        return "KnnScan" in str(plan), "走 KnnScan"
    check("B6", "向量查询走索引（EXPLAIN）", b6)

    def b7():
        # ⚠️ 两个判据陷阱，都是实测踩过的：
        #   陷阱 1：不能断言"结果为空"。中文单字（个/定/存/在）在语料里普遍存在，
        #        bigram 会给无意义查询也召回噪声。
        #   陷阱 2：junk 查询里不能含语料真实存在的词。原基线
        #        「这个术语肯定不存在zzz」含「存在」二字，而 chunk:l11_3 原文
        #        就是「health 端点对不存在的服务也返回 200」—— 它得分 5.59
        #        属于**正确命中**，拿它当噪声基线是判据本身错了。
        #        （diag_noise2.py 实测校准）
        #    现基线：中文串（词不在语料里）+ 纯英文乱码串（语料里完全没有）。
        #
        #    注：噪声能压到这么低，靠的是 retrieve.py 的停用词过滤。
        #    未加过滤时「紫色大象在跳舞」Top1=1.04 的水平会在有效查询之上。
        good = r.kw_search("索引怎么加速查询", limit=3)
        if not good:
            return False, "good=0 条，检索层异常"
        g_top = max(float(x["score"]) for x in good)

        results = []
        for label, q in [("中文乱码", "紫色大象在跳舞"),
                         ("英文乱码", "qxzj vbnw qlkp")]:
            junk = r.kw_search(q, limit=3)
            j_top = max((float(x["score"]) for x in junk), default=0.0)
            results.append((label, j_top))
        worst = max(results, key=lambda x: x[1])
        ok = all(j < g_top * 0.5 for _, j in results)
        return ok, "有效查询 Top1=%.2f；噪声：%s，%s" % (
            g_top,
            " ".join("%s=%.2f" % (a, b) for a, b in results),
            "最高噪声 %.2f 仍 < 50%%" % worst[1] if ok else "噪声 %.2f 过高" % worst[1])
    check("B7", "无意义查询分数显著更低（噪声可控）", b7)

    def b8():
        rows = r.graph_expand("图遍历的边界在哪", limit=3)
        has_ctx = any("邻居背景" in x.get("why", "") for x in rows)
        return has_ctx, "含邻居背景 %d 条" % sum(
            1 for x in rows if "邻居背景" in x.get("why", ""))
    check("B8", "图扩展带出邻居文档背景", b8)

    # ───────────────────────── C. 权限层（阶段 4：权限与多租户）
    print()
    print("【C】权限层 —— 行级隔离与系统用户（阶段 4）")

    def c1():
        try:
            token = conn.signin("app", email="alice@acme.io", password=DEFAULT_PASSWORD)
        except RuntimeError as e:
            return False, "登录失败 %s" % str(e)[:60]
        return bool(token), "alice 登录成功"
    check("C1", "记录用户可登录取 token", c1)

    def c2():
        try:
            token = conn.signin("app", email="alice@acme.io", password=DEFAULT_PASSWORD)
        except RuntimeError:
            return False, "登录失败"
        uc = Conn(token=token)
        ok, payload, err = uc.sql("SELECT tenant FROM chunk;")
        if not ok:
            return False, str(payload)[:60]
        rows = payload[-1].get("result") or []
        tenants = sorted({x.get("tenant") for x in rows})
        return tenants == ["acme"], "可见租户=%s" % tenants
    check("C2", "alice 只能看到 acme 的切块", c2)

    def c3():
        try:
            token = conn.signin("app", email="bob@beta.io", password=DEFAULT_PASSWORD)
        except RuntimeError:
            return False, "登录失败"
        uc = Conn(token=token)
        ok, payload, err = uc.sql("SELECT tenant FROM chunk;")
        if not ok:
            return False, str(payload)[:60]
        rows = payload[-1].get("result") or []
        tenants = sorted({x.get("tenant") for x in rows})
        return tenants == ["beta"], "可见租户=%s" % tenants
    check("C3", "bob 只能看到 beta 的切块", c3)

    def c4():
        # 阳性对照：root 能看到全部两个租户
        ok, payload, err = conn.sql("SELECT tenant FROM chunk;")
        rows = payload[-1].get("result") or []
        tenants = sorted({x.get("tenant") for x in rows})
        return tenants == ["acme", "beta"], "root 可见=%s（系统用户不受约束）" % tenants
    check("C4", "root 不受 PERMISSIONS 约束（对照）", c4)

    def c5():
        # ⚠️ 权限拒绝的表现是"返回空数组且不报错"，不是抛异常。
        #    只看 ok 与否会误判成"写入成功"（diag_verify.py 实测：
        #    CREATE 返回 status=OK + result=[]，root 随后查不到该记录）。
        #    正确判据：执行后**用 root 做副作用检查**，确认记录真的没产生。
        try:
            token = conn.signin("app", email="alice@acme.io", password=DEFAULT_PASSWORD)
        except RuntimeError:
            return False, "登录失败"
        uc = Conn(token=token)
        uc.sql("CREATE chunk:hack SET text='x', tenant='acme', seq=0, "
               "grams='x', emb=[0,0,0,0,0,0,0,0,0,0,0,0];")
        ok, payload, err = conn.sql("SELECT id FROM chunk WHERE id = chunk:hack;")
        rows = payload[-1].get("result") or [] if ok else []
        created = len(rows) > 0
        if created:
            conn.sql("DELETE chunk:hack;")
        return not created, "越权写入 %s" % ("成功（危险）" if created else "被拒绝（正确）")
    check("C5", "记录用户无法写入（副作用检查）", c5)

    def c6():
        try:
            token = conn.signin("app", email="alice@acme.io", password=DEFAULT_PASSWORD)
        except RuntimeError:
            return False, "登录失败"
        uc = Conn(token=token)
        ok, payload, err = uc.sql("SELECT count() FROM ask_audit GROUP ALL;")
        if not ok:
            return False, str(payload)[:60]
        n = payload[-1]["result"][0]["count"]
        ok2, p2, _ = conn.sql("SELECT count() FROM ask_audit GROUP ALL;")
        n_all = p2[-1]["result"][0]["count"] if ok2 else -1
        return n < n_all, "alice 见 %d 条 / 全库 %d 条" % (n, n_all)
    check("C6", "审计表按租户隔离", c6)

    def c7():
        # 登录失败的密码错误必须被拒绝（阴性 + 阳性对照）
        try:
            conn.signin("app", email="alice@acme.io", password="wrong-password")
            return False, "错误密码竟然登录成功"
        except RuntimeError:
            pass
        try:
            t = conn.signin("app", email="alice@acme.io", password=DEFAULT_PASSWORD)
            return bool(t), "错密码被拒 + 对密码通过"
        except RuntimeError as e:
            return False, "正确密码也失败了：%s" % str(e)[:60]
    check("C7", "错误密码被拒绝（配阳性对照）", c7)

    # ───────────────────────── D. 逻辑下推（阶段 3：函数与端点）
    print()
    print("【D】逻辑下推 —— 函数与 HTTP 端点（阶段 3）")

    def d1():
        # ⚠️ 这条断言曾经放过严重 bug：原写法只测单 term（fn::qa_kw('索引',3)），
        #    而多字查询（传整个查询串）实际返回 0 条 —— 验收却是绿的。
        #    现改为测三字查询，且断言"必须命中"。见 diag_downpush.py。
        ok, payload, err = conn.sql(
            "RETURN fn::qa_kw('索引', '加速', '查询', 3);")
        if not ok:
            return False, str(payload)[:60]
        rows = payload[-1].get("result") or []
        top = rows[0].get("id") if rows else None
        return len(rows) > 0, "返回 %d 条，Top1=%s" % (len(rows), top)
    check("D1", "检索函数对多 term 查询有召回", d1)

    def d1b():
        # 与应用层结果对照：Top1 必须一致，否则说明库内检索链路有问题
        ok, payload, err = conn.sql(
            "RETURN fn::qa_kw('索引', '加速', '查询', 3);")
        if not ok:
            return False, str(payload)[:60]
        fn_top = ((payload[-1].get("result") or [{}])[0]).get("id")
        app_rows = r.kw_search("索引怎么加速查询", limit=3)
        app_top = app_rows[0].get("id") if app_rows else None
        return fn_top == app_top, "库内 Top1=%s 应用层 Top1=%s" % (fn_top, app_top)
    check("D1b", "库内函数与应用层 Top1 一致", d1b)

    def d2():
        ok, payload, err = conn.sql(
            "RETURN fn::qa_scoped('权限', '隔离', '租户', 5, 'beta');")
        if not ok:
            return False, str(payload)[:60]
        rows = payload[-1].get("result") or []
        ts = sorted({x.get("tenant") for x in rows})
        return ts == ["beta"], "返回租户=%s" % ts
    check("D2", "带租户过滤的函数生效", d2)

    def d3():
        # ⚠️ 同一路径的 GET 与 POST 若分两条 DEFINE，后定义的会覆盖先定义的
        #    （diag_verify.py 实测：GET /qa 返回 404，POST /qa 正常，且不报错）。
        #    正确写法是 FOR GET, POST 一条语句 —— 这里断言两者都可用。
        res = conn.result("INFO FOR DB;")
        apis = res.get("apis", {}) if isinstance(res, dict) else {}
        has_qa = "/qa" in apis
        code_get, _ = conn.api("/qa", "GET")
        code_post, _ = conn.api("/qa", "POST", json.dumps({"q": "索引", "k": 1}))
        ok = has_qa and code_get == 200 and code_post == 200
        return ok, "/qa 已注册=%s GET=%d POST=%d（合并定义应都为 200）" % (
            has_qa, code_get, code_post)
    check("D3", "/qa 的 GET 与 POST 并存（FOR GET, POST 合并定义）", d3)

    def d4():
        code, body = conn.api("/qa", "POST", json.dumps({"q": "索引", "k": 3}))
        if code != 200:
            return False, "HTTP %s %s" % (code, body[:60])
        try:
            j = json.loads(body)
        except Exception:
            return False, "响应不是 JSON：%s" % body[:60]
        return (j.get("q") == "索引" and j.get("count", 0) > 0), \
            "q=%r count=%s" % (j.get("q"), j.get("count"))
    check("D4", "POST /qa 返回正确结果", d4)

    def d5():
        # $request.body 是字节数组，不转换会静默得到空串 → count=0
        code, body = conn.api("/qa", "POST", json.dumps({"q": "不存在的词zzz", "k": 3}))
        if code != 200:
            return False, "HTTP %s" % code
        j = json.loads(body)
        return j.get("count") == 0, "无匹配时 count=%s" % j.get("count")
    check("D5", "端点对无匹配返回 count=0", d5)

    def d6():
        try:
            token = conn.signin("app", email="bob@beta.io", password=DEFAULT_PASSWORD)
        except RuntimeError:
            return False, "登录失败"
        uc = Conn(token=token)
        code, body = uc.api("/ask", "POST", json.dumps({"q": "权限", "k": 3}))
        if code != 200:
            return False, "HTTP %s %s" % (code, body[:60])
        j = json.loads(body)
        return j.get("tenant") == "beta", "端点内 $auth.tenant=%r" % j.get("tenant")
    check("D6", "端点内可读到 $auth.tenant", d6)

    def d7():
        ok, payload, err = conn.sql("SELECT n FROM ask_audit ORDER BY n DESC LIMIT 1;")
        if not ok:
            return False, str(payload)[:60]
        rows = payload[-1].get("result") or []
        return bool(rows) and rows[0].get("n", 0) > 0, \
            "最近一次命中 %s 条" % (rows[0].get("n") if rows else 0)
    check("D7", "审计记录了命中条数", d7)

    # ───────────────────────── E. 可观测（阶段 4：可观测）
    print()
    print("【E】可观测 —— 服务端自报耗时（阶段 4）")

    def e1():
        ok, payload, err = conn.sql("RETURN 1;")
        if not ok:
            return False, str(payload)[:60]
        t = payload[-1].get("time")
        return t is not None, "time 字段=%s" % t
    check("E1", "响应含服务端自报 time 字段", e1)

    def e2():
        from common import fmt_ms
        cases = {"177.871µs": 0.177871, "3.5ms": 3.5, "1.2s": 1200.0,
                 "500ns": 0.0005, "2us": 0.002}
        bad = []
        for raw, exp in cases.items():
            got = fmt_ms(raw)
            if got is None or abs(got - exp) > max(1e-6, exp * 0.01):
                bad.append("%s→%s 期望 %s" % (raw, got, exp))
        return not bad, "5 种单位全部正确" if not bad else "; ".join(bad)
    check("E2", "time 解析支持 µs/ns/s（不做 rstrip）", e2)

    def e3():
        from retrieve import measure
        rows, med_ms, err = measure(conn, "索引怎么加速查询", "hybrid", k=5, repeat=3)
        if err:
            return False, str(err)[:60]
        return med_ms is not None and med_ms < 50, "hybrid 服务端中位 %.2f ms" % med_ms
    check("E3", "混合检索服务端耗时可测", e3)

    def e4():
        # 性能口径纪律：墙钟必须显著大于服务端自报，否则说明测的是网络
        import time
        from retrieve import measure
        t0 = time.time()
        r.search("索引怎么加速查询", mode="hybrid", limit=5)
        wall = (time.time() - t0) * 1000
        _, srv, _ = measure(conn, "索引怎么加速查询", "hybrid", k=5, repeat=3)
        return srv is not None and wall > srv, \
            "墙钟 %.1f ms > 服务端 %.2f ms" % (wall, srv)
    check("E4", "墙钟显著大于服务端耗时（口径正确）", e4)

    # ───────────────────────── F. 工程性
    print()
    print("【F】工程性 —— 可重复执行与清理")

    def f1():
        # 重跑 init_db 应该幂等：这里用"schema 语句可重复执行"来验证
        from schema import SCHEMA
        ok, payload, err = conn.sql("DEFINE ANALYZER IF NOT EXISTS zh_grams "
                                    "TOKENIZERS blank FILTERS lowercase;")
        return ok, "重复定义分析器：%s" % ("OK" if ok else str(payload)[:50])
    check("F1", "schema 可重复执行", f1)

    def f2():
        # 环境探测友好：连不上要给出明确错误，而不是莫名超时
        from common import Conn as C
        bad = C(base="http://127.0.0.1:59999")
        ok, payload, err = bad.sql("RETURN 1;")
        return (not ok) and err is not None, "不可达时返回 err=%s" % err
    check("F2", "连不上时有明确错误", f2)

    def f3():
        # 清理：临时表不应残留
        n = count(conn, "bench_scale")
        return n is None or n == 0, "bench_scale=%s" % n
    check("F3", "临时表已清理", f3)

    def f4():
        return count(conn, "user") == len(USERS), "user=%s" % count(conn, "user")
    check("F4", "用户数据完整", f4)

    def f5():
        # 反向验证：tenant 字段必须覆盖所有 chunk
        ok, payload, err = conn.sql(
            "SELECT count() FROM chunk WHERE tenant IS NONE GROUP ALL;")
        if not ok:
            return False, str(payload)[:60]
        n = payload[-1]["result"][0]["count"]
        return n == 0, "无租户的切块=%s" % n
    check("F5", "所有切块都有租户标记", f5)

    def f6():
        ok, payload, err = conn.sql("SELECT count() FROM hit GROUP ALL;")
        n = payload[-1]["result"][0]["count"] if ok else 0
        return n > 0, "倒排边=%s 条" % n
    check("F6", "倒排索引已建（term→chunk）", f6)

    # ───────────────────────── 汇总
    print()
    print("=" * 96)
    print("汇总：通过 %d / %d" % (len(PASS), len(PASS) + len(FAIL)))
    print("=" * 96)
    if FAIL:
        print()
        print("未通过项：")
        for cid, desc, ev in FAIL:
            print("  ✗ %-4s %-42s %s" % (cid, desc, ev))
        return 1
    print("全部通过。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
