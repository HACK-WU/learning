# -*- coding: utf-8 -*-
"""诊断：规模敏感性为什么"没反应"？32000 行和 2000 行耗时一样。

最可能的原因：数据根本没灌进去（INSERT 失败被吞了）。
第二可能：耗时取自第一条语句（DELETE/INSERT），不是查询本身。

纪律：先用 count 验证数据真的在，再谈性能。
"""
import sys
import os
import time
import statistics

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn, fmt_ms  # noqa: E402

conn = Conn()


def med(xs):
    return statistics.median(xs) if xs else None


def timed(q, repeat=5):
    ts = []
    for _ in range(repeat):
        ok, payload, err = conn.sql(q)
        if not ok:
            print("      FAIL %s %s" % (err, str(payload)[:180]))
            return None
        for item in payload:
            t = fmt_ms(item.get("time"))
            if t is not None:
                ts.append(t)
    return med(ts)


print("=" * 74)
print("1. 先确认 INSERT ... VALUES 语法能不能用")
print("=" * 74)
conn.sql("REMOVE TABLE IF EXISTS bs;")
ok, payload, err = conn.sql("DEFINE TABLE bs SCHEMAFULL TYPE NORMAL; "
                            "DEFINE FIELD v ON bs TYPE number; "
                            "DEFINE FIELD cat ON bs TYPE string;")
print("  def table:", "OK" if ok else str(payload)[:200])

ok, payload, err = conn.sql("INSERT INTO bs [id, v, cat] VALUES (bs:a1, 1, 'c1');")
print("  insert 单条:", "OK" if ok else "FAIL %s" % str(payload)[:260])
ok, payload, err = conn.sql("SELECT count() FROM bs GROUP ALL;")
print("  count:", payload[-1].get("result") if ok else str(payload)[:200])

print()
print("=" * 74)
print("2. 分档灌数据 + 每档都断言行数")
print("=" * 74)
for n in [2000, 8000, 32000]:
    conn.sql("DELETE bs;")
    ok, payload, err = conn.sql("SELECT count() FROM bs GROUP ALL;")
    after_del = payload[-1]["result"][0]["count"] if ok else "?"
    print("  --- 目标 %d 行（DELETE 后剩 %s）---" % (n, after_del))

    batch, done = 500, 0
    t0 = time.time()
    while done < n:
        size = min(batch, n - done)
        vals = ",".join("(bs:s%d, %d, 'c%d')" % (done + i, i, i % 8)
                        for i in range(size))
        ok, payload, err = conn.sql("INSERT INTO bs [id, v, cat] VALUES %s;" % vals)
        if not ok:
            print("      INSERT 失败 %s" % str(payload)[:200])
            break
        done += size
    dt = time.time() - t0

    ok, payload, err = conn.sql("SELECT count() FROM bs GROUP ALL;")
    real = payload[-1]["result"][0]["count"] if ok else "?"
    print("      实灌 %s 行，用时 %.2fs" % (real, dt))

    for label, q in [
        ("全表聚合", "SELECT cat, count() FROM bs GROUP BY cat;"),
        ("带过滤", "SELECT v FROM bs WHERE cat = 'c3' LIMIT 100;"),
        ("全表 count", "SELECT count() FROM bs GROUP ALL;"),
    ]:
        t = timed(q)
        # 打印返回条数，确认查询真的扫到了东西
        ok2, p2, _ = conn.sql(q)
        cnt = len(p2[-1].get("result") or []) if ok2 and isinstance(p2, list) else "?"
        print("      %-10s %10s ms   返回 %s 组" % (
            label, ("%.2f" % t) if t is not None else "—", cnt))

print()
print("=" * 74)
print("3. 真正的规模测试：用无索引 vs 有索引对比")
print("=" * 74)
conn.sql("REMOVE TABLE IF EXISTS bs;")
conn.sql("DEFINE TABLE bs SCHEMAFULL TYPE NORMAL; "
         "DEFINE FIELD v ON bs TYPE number; "
         "DEFINE FIELD cat ON bs TYPE string;")

n = 50000
batch, done = 1000, 0
t0 = time.time()
while done < n:
    size = min(batch, n - done)
    vals = ",".join("(bs:x%d, %d, 'c%d')" % (done + i, i, i % 50)
                    for i in range(size))
    ok, payload, err = conn.sql("INSERT INTO bs [id, v, cat] VALUES %s;" % vals)
    if not ok:
        print("  INSERT 失败 %s" % str(payload)[:200])
        break
    done += size
print("  灌 %d 行用时 %.2fs" % (done, time.time() - t0))
ok, payload, err = conn.sql("SELECT count() FROM bs GROUP ALL;")
print("  实际行数:", payload[-1]["result"][0]["count"] if ok else "?")

q_filt = "SELECT v FROM bs WHERE cat = 'c7' LIMIT 100;"
t_no_idx = timed(q_filt)
plan = conn.result(q_filt + " EXPLAIN;")
print("  无索引 : %.2f ms   计划含 %s" % (
    t_no_idx, "TableScan" if "TableScan" in str(plan) else
    ("IndexScan" if "IndexScan" in str(plan) else "?")))

conn.sql("DEFINE INDEX idx_bs_cat ON TABLE bs COLUMNS cat;")
time.sleep(0.5)
t_idx = timed(q_filt)
plan2 = conn.result(q_filt + " EXPLAIN;")
print("  有索引 : %.2f ms   计划含 %s" % (
    t_idx, "TableScan" if "TableScan" in str(plan2) else
    ("IndexScan" if "IndexScan" in str(plan2) else "?")))
if t_no_idx and t_idx:
    print("  加速比 : %.1fx" % (t_no_idx / t_idx))

conn.sql("REMOVE TABLE IF EXISTS bs;")
