# -*- coding: utf-8 -*-
"""诊断：为什么「权限怎么配置」召回的不是 l10？

三路结果应该互补，而不是互相稀释。嫌疑：
1. bigram 切分把「权限」切成 权限/限怎/怎么/么配/配置 —— 噪声 term 太多
2. kw 用 OR 组合，噪声 term 把不相关的块也拉进来，稀释了 BM25 有效信号
3. rrf 的 k=2 导致权重衰减过快
"""
import sys
import os
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn, grams_field, embed  # noqa: E402

conn = Conn()


def show(q, tag):
    ok, payload, err = conn.sql(q)
    print("--- %s" % tag)
    if not ok:
        print("    FAIL %s %s" % (err, str(payload)[:260]))
        return None
    last = payload[-1] if payload else {}
    print("    %s" % json.dumps(last.get("result"), ensure_ascii=False)[:520])
    return last.get("result")


Q = "权限怎么配置"
print("=" * 74)
print("问题：%s" % Q)
print("bigram：%s" % grams_field(Q))
print("=" * 74)

print()
print("--- 1. 单个 term 分别查，看谁在捣乱 ---")
for t in grams_field(Q).split():
    show("SELECT id, search::score(0) AS s FROM chunk WHERE grams @@ '%s' LIMIT 3;" % t,
         "term=%s" % t)

print()
print("--- 2. 只查「权限」这个核心 term 的排序 ---")
show("SELECT id, search::score(0) AS s FROM chunk WHERE grams @@ '权限' "
     "ORDER BY s DESC LIMIT 5;", "权限 only")

print()
print("--- 3. 当前实现：8 个 term OR 组合 ---")
terms = grams_field(Q).split()
cond = " OR ".join("grams @@ '%s'" % t for t in terms[:8])
show("SELECT id, search::score(0) AS s FROM chunk WHERE %s ORDER BY s DESC LIMIT 5;" % cond,
     "OR 8 terms")

print()
print("--- 4. 对比：只用长度>=2 且是连续原文子串的 term ---")
# 启发式：只保留既是 bigram 又确实出现在原文里的 term（降低噪声）
core = [t for t in terms if len(t) >= 2]
cond2 = " OR ".join("grams @@ '%s'" % t for t in core[:6])
show("SELECT id, search::score(0) AS s FROM chunk WHERE %s ORDER BY s DESC LIMIT 5;" % cond2,
     "core terms")

print()
print("--- 5. 向量路单独看 ---")
qv = embed(Q)
arr = "[" + ",".join(repr(float(v)) for v in qv) + "]"
show("LET $q = %s; SELECT id, vector::distance::knn() AS d FROM chunk "
     "WHERE emb <|5,80|> $q ORDER BY d ASC LIMIT 5;" % arr, "vec top5")
print("    主题向量非零维度：%s" % [(i, round(v, 3)) for i, v in enumerate(qv) if v > 0])

print()
print("--- 6. l10 的块到底长什么样（它应该被召回）---")
show("SELECT id, text FROM chunk WHERE doc = doc:l10 LIMIT 5;", "l10 chunks")
show("SELECT id, search::score(0) AS s FROM chunk WHERE doc = doc:l10 AND grams @@ '权限';",
     "l10 且含 权限")
