# -*- coding: utf-8 -*-
"""diag_noise2.py —— 重新校准「噪声可控」的判据

上一版（diag_noise.py）选定的 junk 查询选错了：
    "这个术语肯定不存在zzz"
它含有「术语」「肯定」「存在」这些**真实存在于语料**的词，
chunk:l11_3 里就有「不存在」三个字，所以命中是**正确行为**，不是噪声。
用它当"无意义查询"基线，等于拿真信号当噪声，判据本身不成立。

本脚本做三件事：
    Q1 对比多个候选 junk 查询的 Top1 得分，挑出语料里真正不存在的那个
    Q2 验证停用词过滤确实降低了噪声（同一 junk 查询过滤前后对比）
    Q3 确认停用词过滤没有伤害有效查询（Top1 是否仍正确）
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn, grams_field  # noqa: E402
from retrieve import Retriever  # noqa: E402

JUNK_CANDIDATES = [
    "这个术语肯定不存在zzz",
    "紫色大象在跳舞",
    "键盘上的西瓜会唱歌",
    "qxzj vbnw qlkp",
    "这个术语肯定不存在zzz 紫色大象",
]

GOOD_QUERIES = [
    ("索引怎么加速查询", "chunk:l06_0"),
    ("权限隔离怎么做", None),
    ("图关系怎么建", None),
    ("向量检索", None),
]


def main():
    conn = Conn()
    r = Retriever(conn)

    print("=" * 78)
    print("Q1 候选 junk 查询的 Top1 得分（越低越像真噪声）")
    print("=" * 78)
    best = None
    for q in JUNK_CANDIDATES:
        hits = r.kw_search(q, limit=3)
        if not hits:
            print("  %-24s → 0 条（完全不命中）" % q)
            score = 0.0
        else:
            score = float(hits[0].get("score", 0))
            print("  %-24s → Top1=%.2f  %s"
                  % (q, score, hits[0].get("id")))
        if best is None or score < best[1]:
            best = (q, score)
    print()
    print("  最干净的 junk 查询：%r（Top1=%.2f）" % (best[0], best[1]))

    print()
    print("=" * 78)
    print("Q2 停用词过滤前后对比（junk 查询）")
    print("=" * 78)
    for q in JUNK_CANDIDATES[:2] + [best[0]]:
        grams_all = grams_field(q).split()
        terms_kept = r._kw_terms(q)
        hits_raw = r.kw_search(q, limit=1)
        print("  %r" % q)
        print("      原始 grams %d 个 → 过滤后 %d 个：%s"
              % (len(grams_all), len(terms_kept), terms_kept))
        print("      Top1=%.2f" % (float(hits_raw[0]["score"]) if hits_raw else 0.0))

    print()
    print("=" * 78)
    print("Q3 停用词过滤后，有效查询是否仍正确")
    print("=" * 78)
    for q, expect in GOOD_QUERIES:
        hits = r.kw_search(q, limit=3)
        top = hits[0].get("id") if hits else None
        flag = ""
        if expect:
            flag = "  ✓ 命中预期" if top == expect else "  ✗ 期望 %s" % expect
        print("  %-14s → Top1=%-14s score=%.2f%s"
              % (q, top, float(hits[0]["score"]) if hits else 0.0, flag))
        for h in hits[1:]:
            print("                 %-14s score=%.2f"
                  % (h.get("id"), float(h.get("score", 0))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
