# -*- coding: utf-8 -*-
"""diag_fnloop4.py —— 确定库内多 term 检索的可行解（P6 变体对比）

已确定的事实：
    FOR + LET 累积    → 0 条（FOR 内 LET 不写回外层）
    闭包 array::any   → 0 条 / 报错（闭包内 @@ 不算 MATCHES 子句）
    grams @@ 'a b'    → AND 语义，召回骤降
    单 term + score   → 可用（P7）
    两子查询 concat   → 可用但无 score（P6）

待定：P6 变体里，能否在**每个子查询各自**拿到 score，从而保留排序能力？
     P8  各子查询带自己的 score，最后按 score 排序
     P9  各子查询带 score，用 UNION 语义去重后再排序
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn  # noqa: E402

PROBES = [
    ("P8 两条子查询各带 score，外层排序",
     """
     DEFINE FUNCTION OVERWRITE fn::p8($t1: string, $t2: string, $k: number) {
       LET $a = (SELECT id, text, search::score(0) AS s FROM chunk
                 WHERE grams @@ $t1 ORDER BY s DESC LIMIT $k);
       LET $b = (SELECT id, text, search::score(0) AS s FROM chunk
                 WHERE grams @@ $t2 ORDER BY s DESC LIMIT $k);
       LET $all = array::concat($a, $b);
       RETURN (SELECT id, text, math::max(s) AS s
               FROM $all GROUP BY id, text
               ORDER BY s DESC LIMIT $k);
     };
     """,
     "RETURN fn::p8('索引','加速', 5);"),

    ("P9 不用 GROUP BY，直接排序去重后的数组",
     """
     DEFINE FUNCTION OVERWRITE fn::p9($t1: string, $t2: string, $k: number) {
       LET $a = (SELECT id, text, search::score(0) AS s FROM chunk
                 WHERE grams @@ $t1 ORDER BY s DESC LIMIT $k);
       LET $b = (SELECT id, text, search::score(0) AS s FROM chunk
                 WHERE grams @@ $t2 ORDER BY s DESC LIMIT $k);
       RETURN array::sort(array::distinct(array::concat($a, $b)), 's', 'desc');
     };
     """,
     "RETURN fn::p9('索引','加速', 5);"),

    ("P10 对照：应用层 kw_search 的结果",
     None,
     None),
]


def main():
    conn = Conn()
    for desc, ddl, call in PROBES:
        print("=" * 74)
        print(desc)
        if ddl is None:
            from retrieve import Retriever
            rows = Retriever(conn).kw_search("索引怎么加速查询", limit=5)
            for x in rows:
                print("      %-13s score=%.3f %s"
                      % (x.get("id"), float(x.get("score") or 0),
                         (x.get("text") or "")[:36]))
            continue
        ok, payload, err = conn.sql(ddl.strip())
        if not ok:
            print("  定义失败：%s" % str(payload)[:240])
            continue
        ok, payload, err = conn.sql(call)
        if not ok:
            print("  调用失败：%s" % str(payload)[:240])
            continue
        res = payload[-1].get("result")
        n = len(res) if isinstance(res, list) else 0
        print("  → %d 条" % n)
        if isinstance(res, list):
            for x in res[:5]:
                s = x.get("s")
                print("      %-13s score=%s %s"
                      % (x.get("id"),
                         ("%.3f" % float(s)) if isinstance(s, (int, float)) else s,
                         (x.get("text") or "")[:36]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
