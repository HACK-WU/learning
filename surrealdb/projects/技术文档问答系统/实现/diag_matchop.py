# -*- coding: utf-8 -*-
"""diag_matchop.py —— 决定库内全文函数怎么修：先测清 @@ 的多 term 语义

背景（diag_downpush.py 抓出的 P0）：
    fn::qa_kw('索引怎么加速查询', 3) 返回 0 条
    因为 grams @@ $q 会对整个查询串做 tokenize，得到一个巨大的 token，
    grams 字段里当然没有它。

修的前提是搞清楚三件事：
    Q1 grams @@ '索引 加速'（空格分隔两个 term）是 AND 还是 OR？
    Q2 若按空格拆成数组，有没有可用的函数做多 term 匹配？
    Q3 编号绑定 @N@ 能否在库内函数里用变量构造（决定能否动态多 term）
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn  # noqa: E402

PROBES = [
    ("单 term（肯定命中）",
     "SELECT id FROM chunk WHERE grams @@ '索引' LIMIT 5;"),
    ("两个 term 空格分隔（测 AND/OR）",
     "SELECT id FROM chunk WHERE grams @@ '索引 加速' LIMIT 5;"),
    ("两个 term 都极常见（AND 会很多，OR 会更多）",
     "SELECT id FROM chunk WHERE grams @@ '索引 类型' LIMIT 5;"),
    ("不存在的 term + 存在的 term（AND 应为 0，OR 应 >0）",
     "SELECT id FROM chunk WHERE grams @@ '索引 zzzzz' LIMIT 5;"),
    ("编号绑定 @0@ @1@ 固定写法",
     "SELECT id, search::score(0)+search::score(1) AS s FROM chunk "
     "WHERE grams @0@ '索引' OR grams @1@ '加速' ORDER BY s DESC LIMIT 5;"),
    ("数组函数是否可用",
     "RETURN array::len(string::split('索引 加速', ' '));"),
]


def main():
    conn = Conn()
    print("=" * 78)
    print("探测 @@ 的多 term 语义")
    print("=" * 78)
    for desc, q in PROBES:
        ok, payload, err = conn.sql(q)
        if not ok:
            print()
            print("  %s" % desc)
            print("      ✗ %s" % str(payload)[:160])
            continue
        res = payload[-1].get("result") if isinstance(payload, list) else None
        if isinstance(res, list):
            ids = [x.get("id") for x in res] if res and isinstance(res[0], dict) else res
            print()
            print("  %s" % desc)
            print("      %d 条：%s" % (len(res), ids[:5]))
        else:
            print()
            print("  %s" % desc)
            print("      返回：%s" % str(res)[:120])

    print()
    print("=" * 78)
    print("判读：")
    print("  「索引 zzzzz」若返回 >0 → OR 语义，库内可传多 term")
    print("  「索引 zzzzz」若返回 =0 → AND 语义，库内多 term 会召回骤降")
    print("=" * 78)
    return 0


if __name__ == "__main__":
    sys.exit(main())
