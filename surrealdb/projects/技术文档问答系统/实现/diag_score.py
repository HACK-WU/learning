# -*- coding: utf-8 -*-
"""诊断：多 term OR 时 search::score(0) 全 0 的根因与正确写法。

假设（来自课 6）：多条件时必须用 @N@ 编号绑定，search::score(N) 对应第 N 个
匹配表达式。没编号时，每个 OR 分支各自一个编号，score(0) 只反映第一个分支，
命中其它分支的记录 score(0) 就是 0 —— 于是 ORDER BY score 退化成任意顺序。
"""
import sys
import os
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn, grams_field  # noqa: E402

conn = Conn()


def show(q, tag):
    ok, payload, err = conn.sql(q)
    print("--- %s" % tag)
    if not ok:
        print("    FAIL %s %s" % (err, str(payload)[:300]))
        return None
    last = payload[-1] if payload else {}
    print("    %s" % json.dumps(last.get("result"), ensure_ascii=False)[:560])
    return last.get("result")


Q = "权限怎么配置"
terms = grams_field(Q).split()
print("=" * 74)
print("问题：%s   terms=%s" % (Q, terms))
print("=" * 74)

print()
print("--- 1. 复现：无编号 OR，score(0) ---")
cond = " OR ".join("grams @@ '%s'" % t for t in terms[:6])
show("SELECT id, search::score(0) AS s FROM chunk WHERE %s ORDER BY s DESC LIMIT 6;" % cond,
     "无编号 score(0)")

print()
print("--- 2. 编号绑定 @N@，各分支单独打分 ---")
parts = []
for i, t in enumerate(terms[:6]):
    parts.append("grams @%d@ '%s'" % (i, t))
cond2 = " OR ".join(parts)
score_expr = " + ".join("search::score(%d)" % i for i in range(len(terms[:6])))
show("SELECT id, (%s) AS s FROM chunk WHERE %s ORDER BY s DESC LIMIT 6;"
     % (score_expr, cond2), "编号 score 求和")

print()
print("--- 3. 只保留在语料里真实存在的 term（去噪）---")
for t in terms:
    r = show("SELECT count() FROM chunk WHERE grams @@ '%s' GROUP ALL;" % t,
             "term %s 命中数" % t)

print()
print("--- 4. 去噪后编号求和：只留长度>=2 的 bigram ---")
core = [t for t in terms if len(t) >= 2]
print("    core=%s" % core)
parts = ["grams @%d@ '%s'" % (i, t) for i, t in enumerate(core)]
cond3 = " OR ".join(parts)
se3 = " + ".join("search::score(%d)" % i for i in range(len(core)))
show("SELECT id, (%s) AS s FROM chunk WHERE %s ORDER BY s DESC LIMIT 6;"
     % (se3, cond3), "去噪+编号")

print()
print("--- 5. 混合策略：bigram 优先，不足时用单字补 ---")
core = [t for t in terms if len(t) >= 2]
single = [t for t in terms if len(t) == 1]
allt = core + single
parts = ["grams @%d@ '%s'" % (i, t) for i, t in enumerate(allt)]
cond4 = " OR ".join(parts)
# 给 bigram 更高权重：bigram 1.0，单字 0.3
weights = [1.0] * len(core) + [0.3] * len(single)
se4 = " + ".join("%.1f * search::score(%d)" % (w, i)
                 for i, w in enumerate(weights))
show("SELECT id, (%s) AS s FROM chunk WHERE %s ORDER BY s DESC LIMIT 6;"
     % (se4, cond4), "加权 bigram>单字")

print()
print("--- 6. 验证：不同问题下加权方案的表现 ---")
for q in ["权限怎么配置", "图遍历怎么写", "向量检索怎么混合", "存储后端选哪个",
          "实时推送怎么做", "事务怎么回滚"]:
    tms = grams_field(q).split()
    core = [t for t in tms if len(t) >= 2]
    single = [t for t in tms if len(t) == 1]
    allt = (core + single)[:10]
    if not allt:
        continue
    parts = ["grams @%d@ '%s'" % (i, t) for i, t in enumerate(allt)]
    c = " OR ".join(parts)
    w = [1.0] * min(len(core), 10) + [0.3] * max(0, len(allt) - min(len(core), 10))
    se = " + ".join("%.1f * search::score(%d)" % (w[i], i) for i in range(len(allt)))
    r = conn.result("SELECT id, (%s) AS s FROM chunk WHERE %s ORDER BY s DESC LIMIT 3;"
                    % (se, c))
    top = ", ".join("%s(%.2f)" % (x["id"].replace("chunk:", ""), x["s"])
                    for x in (r or []))
    print("    %-14s → %s" % (q, top))
