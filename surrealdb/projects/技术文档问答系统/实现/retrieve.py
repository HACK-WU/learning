# -*- coding: utf-8 -*-
"""retrieve.py —— 检索层：四种检索模式 + 图扩展 + 融合

这是整个项目的技术核心。四种模式不是摆设，是为了回答一个问题：
    **为什么单靠一种检索不够，必须混合？**

  kw      关键词（中文 bigram 走 FULLTEXT + BM25）
  vec     向量（主题向量走 HNSW + COSINE）
  hybrid  混合（search::rrf 融合前两者）
  graph   图扩展（先混合召回，再沿 refs 边取邻居文档的块）

每条查询函数都返回统一结构：
    { id, text, doc, tenant, seq, score, why }
why 字段说明这条结果是被哪一路召回的 —— 便于肉眼验证融合是否真的互补。
"""
import sys
import os
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn, grams_field, embed, fmt_ms  # noqa: E402


def _rows(result):
    return result if isinstance(result, list) else []


class Retriever:
    def __init__(self, conn, tenant=None, k=8):
        self.conn = conn
        self.tenant = tenant      # None = 走 root，不过滤租户
        self.k = k

    # ---------------------------------------------------------- 基础检索

    # bigram 权重高，单字权重低：单字（如「的」「怎么」里的字）命中面太广，
    # 等权会把噪声块拉进前列（diag_score.py 实测：等权时 l06_3 因单字「置」排第一，
    # 加权后正确的 l09_0 / l10_1 回到前二）
    W_BIGRAM = 1.0
    W_SINGLE = 0.3

    # ⚠️ 停用词：加权不够，必须过滤（verify.py B7 实测的真缺陷）。
    #    仅靠 0.3 的低权重，无意义串「这个术语肯定不存在zzz」里的
    #    「不」「存」「在」仍能累加出 5.59 分，反超有效查询「索引怎么加速查询」
    #    的 5.35 分 —— 因为「不」出现在 24/48 个块里（50%），「在」16/48（33%）。
    #    diag_noise.py 统计出的语料高频字即是噪声源，这里显式列掉。
    STOPWORDS = set(
        "的 了 是 在 和 与 及 或 就 都 而 及 其 之 于 对 由 被 把 给 让 使 "
        "我 你 他 她 它 们 这 那 个 些 有 没 不 也 还 很 太 更 最 又 再 才 "
        "要 会 能 可 以 所 用 到 说 做 如 但 并 且 因 所 从 向 为 中 上 下 "
        "一 二 三 四 五 六 七 八 九 十 什么 怎么 这个 那个 可以 因为 所以 "
        "如果 就是 还是 但是 然后 一个 我们 你们 他们".split())

    def _kw_terms(self, question, max_terms=10):
        """bigram 优先、单字补齐的 term 列表，过滤停用词。

        ⚠️ 过滤顺序：先去停用词，再排列优先级、再截断。
           若先截断后过滤，停用词会先占掉 max_terms 的名额，
           长查询里真正有区分度的 bigram 反而被挤掉。

        ⚠️ 降级：若整个查询被过滤成空（如"的的的"），退回未过滤版本。
           宁可返回噪声，也不能让查询直接变成 0 条 —— 后者在端点上
           表现为 count=0，看起来像服务故障。
        """
        grams = grams_field(question).split()
        kept = [t for t in grams if t not in self.STOPWORDS]
        if not kept:
            kept = grams
        bigram = [t for t in kept if len(t) >= 2]
        single = [t for t in kept if len(t) == 1]
        return (bigram + single)[:max_terms]

    def _kw_score_expr(self, terms):
        """生成 (1.0*search::score(0) + 0.3*search::score(3) + ...) 表达式。"""
        parts = []
        for i, t in enumerate(terms):
            w = self.W_BIGRAM if len(t) >= 2 else self.W_SINGLE
            parts.append("%.1f * search::score(%d)" % (w, i))
        return " + ".join(parts) if parts else "0"

    def _kw_where(self, terms):
        """生成 grams @0@ 'x' OR grams @1@ 'y' ... 条件。

        ⚠️ 必须用 @N@ 编号绑定。写成 grams @@ 'x' OR grams @@ 'y' 时，
           search::score(0) 只对应第一个匹配表达式，命中其它分支的记录
           分数恒为 0 —— ORDER BY score 退化成任意顺序（diag_score.py 实测）。
        """
        return " OR ".join(
            "grams @%d@ '%s'" % (i, t.replace("'", "\\'"))
            for i, t in enumerate(terms))

    def kw_search(self, question, limit=None):
        """关键词检索：中文 bigram 走 FULLTEXT 索引，BM25 加权打分。

        ⚠️ 查的是 grams 字段不是 text 字段。3.2.4 内置分析器切不开中文，
           对 text 建索引查中文一条都查不到（cap-probe5-zh2.py 决定性实验）。
        """
        limit = limit or self.k
        terms = self._kw_terms(question)
        if not terms:
            return []
        q = ("SELECT id, text, doc, tenant, seq, (%s) AS score "
             "FROM chunk WHERE %s ORDER BY score DESC LIMIT %d;"
             % (self._kw_score_expr(terms), self._kw_where(terms), limit))
        rows = _rows(self.conn.result(q))
        for r in rows:
            r["why"] = "kw"
            r["score"] = round(float(r.get("score") or 0.0), 6)
        return rows

    def vec_search(self, question, limit=None):
        """向量检索：主题向量走 HNSW 索引。

        ⚠️ 查询向量必须先 LET 再引用，直接内联数组会报 Parse error
           （课 12 实测）。距离用 vector::distance::knn()，它只能配合
           KNN 算子使用。
        """
        limit = limit or self.k
        qv = embed(question)
        arr = "[" + ",".join(repr(float(v)) for v in qv) + "]"
        q = ("LET $q = %s; "
             "SELECT id, text, doc, tenant, seq, "
             "vector::distance::knn() AS dist "
             "FROM chunk WHERE emb <|%d,80|> $q ORDER BY dist ASC LIMIT %d;"
             % (arr, limit, limit))
        rows = _rows(self.conn.result(q))
        for r in rows:
            r["why"] = "vec"
            dist = r.get("dist")
            # 距离转相似度：COSINE 距离 0=完全相同，1=正交
            r["score"] = round(1.0 - float(dist), 6) if dist is not None else 0.0
        return rows

    def hybrid(self, question, limit=None):
        """混合检索：search::rrf 融合关键词与向量两路。

        ⚠️ 签名是 search::rrf(结果数组, limit, k) —— 第二个参数是 limit
           （课 7 决定性实验推翻了初判的 (lists, k, limit)）。
        """
        limit = limit or self.k
        qv = embed(question)
        arr = "[" + ",".join(repr(float(v)) for v in qv) + "]"
        terms = self._kw_terms(question)
        if not terms:
            return self.vec_search(question, limit)
        cond = self._kw_where(terms)
        q = ("LET $q = %s; "
             "LET $kw = (SELECT id, (%s) AS score FROM chunk WHERE %s "
             "ORDER BY score DESC LIMIT %d); "
             "LET $vec = (SELECT id FROM chunk WHERE emb <|%d,80|> $q LIMIT %d); "
             "RETURN search::rrf([$kw, $vec], %d, 2);"
             % (arr, self._kw_score_expr(terms), cond,
                limit * 2, limit * 2, limit * 2, limit))
        fused = _rows(self.conn.result(q))
        ids = [r.get("id") for r in fused if r.get("id")]
        if not ids:
            return []
        scores = {r.get("id"): r.get("rrf_score") for r in fused}
        # 回查正文（rrf 只返回 id 与分数）
        idlist = ",".join(ids)
        q2 = "SELECT id, text, doc, tenant, seq FROM chunk WHERE id IN [%s];" % idlist
        detail = {r["id"]: r for r in _rows(self.conn.result(q2))}
        out = []
        for i in ids:
            d = detail.get(i)
            if not d:
                continue
            d = dict(d)
            d["score"] = round(float(scores.get(i) or 0.0), 6)
            d["why"] = "hybrid"
            out.append(d)
        out.sort(key=lambda r: -r["score"])
        return out

    # ---------------------------------------------------------- 图扩展

    def graph_expand(self, question, limit=None, depth=1):
        """图扩展：先混合召回拿到文档，再沿 refs 边取邻居文档的块加入上下文。

        为什么需要它：单独一个切块常常说不清楚，它引用的那篇文档能提供背景。
        这正是 SurrealDB 相对"向量库 + 另一套图库"的优势 —— 一次查询搞定。

        ⚠️ 深度必须限制。边数按扇出的幂次增长，本项目 refs 扇出约 1，
           但换成真实知识图谱（扇出 10）第 5 跳就是 10 万条（课 12 崩点一）。
        """
        limit = limit or self.k
        base = self.hybrid(question, limit)
        if not base:
            return base

        doc_ids = sorted({r["doc"] for r in base if r.get("doc")})
        if not doc_ids:
            return base

        # 沿 refs 双向取邻居（-> 出边，<- 入边）
        # ⚠️ 必须用 conn.sql() 遍历**每一条**语句的响应。
        #    conn.result() 只返回最后一条语句的 result —— 一次发"出边 + 入边"
        #    两条语句时，入边为空会覆盖掉出边的结果，于是明明有邻居却说没有
        #    （diag_graph.py 抓出：单发 l05 出边能拿到 doc:l04，合在一起就是空）。
        neighbors = set()
        for d in doc_ids:
            q = ("SELECT id FROM %s->refs->doc; "
                 "SELECT id FROM %s<-refs<-doc;" % (d, d))
            ok, payload, err = self.conn.sql(q)
            if not ok or not isinstance(payload, list):
                continue
            for part in payload:
                if not isinstance(part, dict) or part.get("status") != "OK":
                    continue
                for row in _rows(part.get("result")):
                    if row.get("id"):
                        neighbors.add(str(row["id"]))

        neighbors -= set(str(d) for d in doc_ids)
        if not neighbors:
            for r in base:
                r["why"] = "graph(无邻居)"
            return base

        # 邻居文档的第一块作为背景（只取 seq=0，避免上下文爆炸）
        idlist = ",".join(sorted(neighbors))
        qd = ("SELECT id, text, doc, tenant, seq FROM chunk "
              "WHERE doc IN [%s] AND seq = 0 LIMIT %d;" % (idlist, limit))
        try:
            ctx = _rows(self.conn.result(qd))
        except Exception:
            ctx = []

        for r in ctx:
            r["why"] = "graph(邻居背景)"
            r["score"] = 0.0

        # 背景放后面，避免压过真正命中的块
        base.extend(ctx)
        return base[: limit + len(ctx)]

    # ---------------------------------------------------------- 统一入口

    def search(self, question, mode="hybrid", limit=None):
        if mode == "kw":
            return self.kw_search(question, limit)
        if mode == "vec":
            return self.vec_search(question, limit)
        if mode == "graph":
            return self.graph_expand(question, limit)
        return self.hybrid(question, limit)


def measure(conn, question, mode, tenant=None, k=8, repeat=3):
    """跑一次检索并返回（结果, 服务端自报耗时中位数 ms）。

    ⚠️ 性能口径用服务端自报的 time 字段，不用客户端墙钟。
       课 12 实测：HTTP 空操作基线 22.97ms，客户端测量会被往返开销淹没，
       四个不同性质的查询在墙钟下都是 24-27ms —— 看起来"太整齐"本身就是警报。
    """
    r = Retriever(conn, tenant=tenant, k=k)
    all_times = []
    rows = []
    for _ in range(repeat):
        # 用 Retriever 的真实路径执行，保证对比结果与实际查询完全一致
        # （_run_capture 只用于抓 time 字段，正文与分数仍走 Retriever）
        rows = r.search(question, mode=mode, limit=k)
        ok, payload, err = _run_capture(conn, r, question, mode)
        if not ok:
            return None, None, err
        _, times = payload
        all_times.extend(times)
    times = [t for t in all_times if t is not None]
    med = sorted(times)[len(times) // 2] if times else None
    return rows, med, None


def _run_capture(conn, retriever, question, mode):
    """执行一次检索并抓取响应里的 time 字段。

    由于 conn.result() 丢掉了 time，这里直接调 sql() 拿原始响应。
    """
    grams = grams_field(question)
    terms = [t for t in grams.split() if t]
    qv = embed(question)
    arr = "[" + ",".join(repr(float(v)) for v in qv) + "]"

    if mode == "kw":
        terms = retriever._kw_terms(question)
        if not terms:
            return True, ([], []), None
        q = ("SELECT id, text, doc, tenant, seq, (%s) AS score "
             "FROM chunk WHERE %s ORDER BY score DESC LIMIT %d;"
             % (retriever._kw_score_expr(terms),
                retriever._kw_where(terms), retriever.k))
    elif mode == "vec":
        q = ("LET $q = %s; SELECT id, text, doc, tenant, seq, "
             "vector::distance::knn() AS dist FROM chunk "
             "WHERE emb <|%d,80|> $q ORDER BY dist ASC LIMIT %d;"
             % (arr, retriever.k, retriever.k))
    else:  # hybrid
        terms = retriever._kw_terms(question)
        if not terms:
            return True, ([], []), None
        cond = retriever._kw_where(terms)
        q = ("LET $q = %s; "
             "LET $kw = (SELECT id, (%s) AS score FROM chunk WHERE %s "
             "ORDER BY score DESC LIMIT %d); "
             "LET $vec = (SELECT id FROM chunk WHERE emb <|%d,80|> $q LIMIT %d); "
             "RETURN search::rrf([$kw, $vec], %d, 2);"
             % (arr, retriever._kw_score_expr(terms), cond,
                retriever.k * 2, retriever.k * 2, retriever.k * 2, retriever.k))

    ok, payload, err = conn.sql(q)
    if not ok:
        return False, None, err
    times = [fmt_ms(item.get("time")) for item in payload if isinstance(item, dict)]
    last = payload[-1] if payload else {}
    rows = last.get("result") if isinstance(last, dict) and last.get("status") == "OK" else []
    if not isinstance(rows, list):
        rows = []
    if mode == "vec":
        for r in rows:
            d = r.get("dist")
            r["score"] = round(1.0 - float(d), 6) if d is not None else 0.0
    return True, (rows, times), None
