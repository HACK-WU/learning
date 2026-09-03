# -*- coding: utf-8 -*-
"""diag_noise.py —— 诊断为什么"无意义查询"反而得分更高

现象（verify.py B7）：
    junk = "这个术语肯定不存在zzz"  → Top1 = 5.59
    good = "索引怎么加速查询"        → Top1 = 5.35

这不是断言写错，是 bigram 方案的真实噪声：无意义串里含「个」「定」等
高频字，命中大量文档，权重累加后反而超过有效查询。

本脚本回答三个问题：
    Q1 两个查询各自生成了哪些 gram，权重分别多少
    Q2 Top1 文档各自命中了哪些 gram
    Q3 语料里哪些 gram 的文档频率最高（真正的噪声源）
"""
import sys
import os
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn, bigrams  # noqa: E402
from retrieve import Retriever  # noqa: E402


def main():
    conn = Conn()
    r = Retriever(conn)

    junk_q = "这个术语肯定不存在zzz"
    good_q = "索引怎么加速查询"

    print("=" * 74)
    print("Q1 两个查询生成的 gram")
    print("=" * 74)
    for name, q in [("junk", junk_q), ("good", good_q)]:
        g = bigrams(q)
        print("  %-5s %r" % (name, q))
        print("        grams=%s" % g)

    print()
    print("=" * 74)
    print("Q2 Top1 文档与得分构成")
    print("=" * 74)
    for name, q in [("junk", junk_q), ("good", good_q)]:
        hits = r.kw_search(q, limit=3)
        print("  %s  Top%d：" % (name, len(hits)))
        for h in hits:
            print("      %-14s score=%.2f  %s"
                  % (h.get("id"), float(h.get("score", 0)),
                     (h.get("text") or "")[:40]))

    print()
    print("=" * 74)
    print("Q3 语料里文档频率最高的 gram（噪声源）")
    print("=" * 74)
    ok, payload, err = conn.sql(
        "SELECT grams FROM chunk;")
    if not ok:
        print("  读取失败 %s" % str(payload)[:200])
        return 1
    rows = payload[-1].get("result") or []
    df = Counter()
    for row in rows:
        seen = set((row.get("grams") or "").split())
        df.update(seen)
    total = len(rows)
    print("  语料共 %d 块，出现频率 Top15 的 gram：" % total)
    for gram, n in df.most_common(15):
        print("      %-4s 出现在 %3d 块（%.0f%%）" % (gram, n, 100.0 * n / total))
    return 0


if __name__ == "__main__":
    sys.exit(main())
