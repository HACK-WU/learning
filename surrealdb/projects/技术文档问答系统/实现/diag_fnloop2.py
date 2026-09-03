# -*- coding: utf-8 -*-
"""diag_fnloop2.py —— 查清 FOR 循环版为什么返回 0 条，并测试替代写法

diag_fnloop.py 结果：
    fn::qa_one('索引', 3)      → 3 条（可用）
    fn::qa_terms(['索引','加速'], 3) → 0 条（FOR 循环版失败）

同一段 SELECT 放进 FOR 就失效，怀疑是 FOR 内 LET 的作用域问题：
    SurrealQL 的 LET 在 FOR 块内可能每次迭代都新建绑定，
    外层 $out 不被累积。

本脚本一次测四种写法，找出库内多 term 的唯一可行解：
    P1  FOR + LET 累积（已知失败，作为对照）
    P2  FOR 内直接 RETURN（看单次迭代是否有结果）
    P3  SELECT 里用闭包 array::any()
    P4  把 terms 拼成字符串后 @@ 匹配（AND 语义，预期召回低）
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn  # noqa: E402

PROBES = [
    ("P2 FOR 内 RETURN 单次迭代",
     """
     DEFINE FUNCTION OVERWRITE fn::p2($terms: array<string>, $k: number) {
       FOR $t IN $terms {
         RETURN (SELECT id FROM chunk WHERE grams @@ $t LIMIT $k);
       };
     };
     """,
     "RETURN fn::p2(['索引'], 3);"),

    ("P3 闭包 array::any",
     """
     DEFINE FUNCTION OVERWRITE fn::p3($terms: array<string>, $k: number) {
       RETURN (SELECT id, text, search::score(0) AS s FROM chunk
               WHERE array::any($terms, |$t| grams @@ $t)
               ORDER BY s DESC LIMIT $k);
     };
     """,
     "RETURN fn::p3(['索引','加速'], 3);"),

    ("P4 拼串 @@ 匹配（AND 语义对照）",
     """
     DEFINE FUNCTION OVERWRITE fn::p4($s: string, $k: number) {
       RETURN (SELECT id, text, search::score(0) AS s FROM chunk
               WHERE grams @@ $s ORDER BY s DESC LIMIT $k);
     };
     """,
     "RETURN fn::p4('索引 加速', 3);"),
]


def main():
    conn = Conn()
    for desc, ddl, call in PROBES:
        print("=" * 74)
        print(desc)
        ok, payload, err = conn.sql(ddl.strip())
        if not ok:
            print("  定义失败：%s" % str(payload)[:220])
            continue
        ok, payload, err = conn.sql(call)
        if not ok:
            print("  调用失败：%s" % str(payload)[:220])
            continue
        res = payload[-1].get("result")
        n = len(res) if isinstance(res, list) else 0
        print("  → %d 条" % n)
        if isinstance(res, list):
            for x in res[:4]:
                print("      %-13s %s" % (x.get("id"),
                                          (x.get("text") or "")[:40]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
