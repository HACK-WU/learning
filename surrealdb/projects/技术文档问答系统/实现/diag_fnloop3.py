# -*- coding: utf-8 -*-
"""diag_fnloop3.py —— 库内多 term 检索的最终方案测试

前情：
    P1 FOR + LET 累积      → 0 条（FOR 内 LET 不累积到外层）
    P2 FOR 内 RETURN       → 3 条（只返回第一次迭代）
    P3 闭包 array::any     → 报错：no MATCHES clause found（闭包内 @@ 不算 MATCHES）
    P4 拼串 @@ 匹配        → 0 条（AND 语义）

P3 的报错是关键线索：search::score() 只在**顶层 MATCHES 语法**下可用。
闭包里写 @@ 引擎不认，但**用变量**传进去呢？这就是 P5。

若 P5 可行，库内多 term 就有解：把每个 term 查一遍再合并，
虽然拿不到 @N@ 的加权，但至少有 OR 语义的召回。

备选方案 P6：不用 search::score，改用固定的字面量排序（牺牲相关性排序，保召回）。
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn  # noqa: E402

PROBES = [
    ("P5 闭包内 @@ 但不用 score（只测召回）",
     """
     DEFINE FUNCTION OVERWRITE fn::p5($terms: array<string>, $k: number) {
       RETURN (SELECT id, text FROM chunk
               WHERE array::any($terms, |$t| grams @@ $t)
               LIMIT $k);
     };
     """,
     "RETURN fn::p5(['索引','加速'], 5);"),

    ("P6 多层嵌套子查询合并（不用闭包）",
     """
     DEFINE FUNCTION OVERWRITE fn::p6($t1: string, $t2: string, $k: number) {
       LET $a = (SELECT id, text FROM chunk WHERE grams @@ $t1 LIMIT $k);
       LET $b = (SELECT id, text FROM chunk WHERE grams @@ $t2 LIMIT $k);
       RETURN array::distinct(array::concat($a, $b));
     };
     """,
     "RETURN fn::p6('索引','加速', 3);"),

    ("P7 单 term + 应用层多次调用（对照组，已知可用）",
     """
     DEFINE FUNCTION OVERWRITE fn::p7($t: string, $k: number) {
       RETURN (SELECT id, text, search::score(0) AS s FROM chunk
               WHERE grams @@ $t ORDER BY s DESC LIMIT $k);
     };
     """,
     "RETURN fn::p7('索引', 3);"),
]


def main():
    conn = Conn()
    verdict = {}
    for desc, ddl, call in PROBES:
        print("=" * 74)
        print(desc)
        ok, payload, err = conn.sql(ddl.strip())
        if not ok:
            print("  定义失败：%s" % str(payload)[:220])
            verdict[desc[:2]] = "定义失败"
            continue
        ok, payload, err = conn.sql(call)
        if not ok:
            print("  调用失败：%s" % str(payload)[:220])
            verdict[desc[:2]] = "调用失败"
            continue
        res = payload[-1].get("result")
        n = len(res) if isinstance(res, list) else 0
        print("  → %d 条" % n)
        if isinstance(res, list):
            for x in res[:4]:
                print("      %-13s score=%s %s"
                      % (x.get("id"), x.get("s"),
                         (x.get("text") or "")[:36]))
        verdict[desc[:2]] = "%d 条" % n

    print()
    print("=" * 74)
    print("汇总")
    for k, v in verdict.items():
        print("  %s  %s" % (k, v))
    return 0


if __name__ == "__main__":
    sys.exit(main())
