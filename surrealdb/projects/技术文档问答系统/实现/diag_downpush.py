# -*- coding: utf-8 -*-
"""diag_downpush.py —— 验证「设计决策 5」的断言：库内函数精度是否真的更低

设计决策 5 里我写了一句断言：
    「库内函数的召回精度低于应用层生成的版本」

这是评审时发现的**未经实测的断言** —— 我是从原理推的：
应用层把查询切成 bigram（索引/引怎/怎么/...）再去匹配 grams 字段，
而库内 fn::qa_kw 只能拿查询串整体去 @@ 匹配。

本脚本决定性地测一次，回答：
    Q1 对同一批查询，库内函数与应用层检索的 Top1 是否一致
    Q2 不一致时，谁的更相关（人眼看文本判断）
    Q3 差异的机理是什么（打印两边实际用到的匹配串）

若断言不成立，设计决策 5 必须改写 —— 不能留下没验证过的结论。
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn, grams_field  # noqa: E402
from retrieve import Retriever  # noqa: E402

QUERIES = [
    "索引怎么加速查询",
    "权限隔离怎么做",
    "图关系怎么建",
    "向量检索用什么距离函数",
    "端点怎么定义",
]


def main():
    conn = Conn()
    r = Retriever(conn)

    agree = 0
    print("=" * 78)
    print("库内函数 fn::qa_kw  vs  应用层 kw_search")
    print("=" * 78)

    for q in QUERIES:
        # 应用层：bigram 加权 + @N@ 编号绑定
        app_rows = r.kw_search(q, limit=3)

        # 库内函数：接收应用层生成的 term（修复后的正确用法）
        terms = r._kw_terms(q)
        t = (terms + ["", "", ""])[:3]
        safe = [x.replace("'", "\\'") for x in t]
        ok, payload, err = conn.sql(
            "RETURN fn::qa_kw('%s', '%s', '%s', 3);" % tuple(safe))
        fn_rows = (payload[-1].get("result") or []) if ok else []

        app_top = app_rows[0].get("id") if app_rows else None
        fn_top = fn_rows[0].get("id") if fn_rows else None
        same = app_top == fn_top
        agree += 1 if same else 0

        print()
        print("  查询：%s" % q)
        print("      应用层 grams：%s" % " ".join(r._kw_terms(q)))
        print("      库内接收 term：%s" % t)
        print("      应用层 Top1 = %s" % app_top)
        print("      库内   Top1 = %s      %s"
              % (fn_top, "一致" if same else "★ 不一致"))
        if app_rows:
            print("          应用层：%s"
                  % (app_rows[0].get("text") or "")[:40])
        if fn_rows:
            print("          库内　：%s"
                  % (fn_rows[0].get("text") or "")[:40])

    print()
    print("=" * 78)
    print("结论：%d/%d 个查询 Top1 一致" % (agree, len(QUERIES)))
    print("=" * 78)
    if agree == len(QUERIES):
        print("  ⚠️ 断言不成立：库内函数与应用层结果一致，")
        print("     设计决策 5 里「精度更低」的说法必须改写。")
    else:
        print("  断言成立：有 %d 个查询 Top1 不同。" % (len(QUERIES) - agree))
    return 0


if __name__ == "__main__":
    sys.exit(main())
