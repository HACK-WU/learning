# -*- coding: utf-8 -*-
"""diag_fnloop.py —— 测库内函数能否做多 term 检索（FOR 循环累积 vs 其他写法）

结论前置（diag_matchop.py）：grams @@ 是 **AND** 语义。
    所以 `grams @@ '索引 加速'` 要求一块里同时有这两个 gram，召回骤降；
    库内函数直接匹配整个查询串必然 0 条。

应用层的解法是 @N@ 编号绑定（OR + 加权），但 @N@ 是**语法层面的**，
无法用变量动态构造 —— 库内函数拿不到这个能力。

于是只剩两条路：
    方案 A  函数只接收单个 term（召回靠应用层多次调用）
    方案 B  函数接收 term 数组，函数内 FOR 循环累积

本脚本测方案 B 是否可行。
"""
import sys
import os
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn  # noqa: E402

# 方案 B：FOR 循环累积。注意 SurrealQL 的 FOR 语法与变量作用域
FN_LOOP = """
DEFINE FUNCTION OVERWRITE fn::qa_terms($terms: array<string>, $k: number) {
  LET $out = [];
  FOR $t IN $terms {
    LET $hit = (
      SELECT id, text, doc, tenant, seq, search::score(0) AS s
      FROM chunk WHERE grams @@ $t
      ORDER BY s DESC LIMIT $k
    );
    LET $out = array::concat($out, $hit);
  };
  RETURN $out;
};
"""

# 对照：单 term 版本（已知可用）
FN_ONE = """
DEFINE FUNCTION OVERWRITE fn::qa_one($t: string, $k: number) {
  LET $hit = (
    SELECT id, text, doc, tenant, seq, search::score(0) AS s
    FROM chunk WHERE grams @@ $t
    ORDER BY s DESC LIMIT $k
  );
  RETURN $hit;
};
"""


def main():
    conn = Conn()

    for name, ddl in [("fn::qa_terms（FOR 循环）", FN_LOOP),
                      ("fn::qa_one（单 term）", FN_ONE)]:
        ok, payload, err = conn.sql(ddl.strip())
        print("=" * 74)
        print("定义 %s：%s" % (name, "OK" if ok else "失败"))
        if not ok:
            print("      %s" % str(payload)[:300])
            continue

        if "terms" in name:
            args = "['索引', '加速'], 3"
        else:
            args = "'索引', 3"
        ok, payload, err = conn.sql("RETURN fn::qa_%s(%s);"
                                    % ("terms" if "terms" in name else "one", args))
        if not ok:
            print("      调用失败：%s" % str(payload)[:300])
            continue
        res = payload[-1].get("result")
        n = len(res) if isinstance(res, list) else 0
        print("      返回 %d 条" % n)
        if isinstance(res, list):
            for x in res[:4]:
                print("          %-13s %s" % (x.get("id"),
                                              (x.get("text") or "")[:40]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
