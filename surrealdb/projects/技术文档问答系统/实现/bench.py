# -*- coding: utf-8 -*-
"""bench.py —— 可观测：把「这个系统快不快」变成可验证的数字

本脚本刻意贯彻课 12 的三条测量纪律，任何一条不做就会得出错误结论：

1. 先测空操作基线。HTTP 往返约 23ms，不测基线就无法判断 24ms 到底是
   「查询慢」还是「路远」。
2. 用服务端自报的 time 字段，不用客户端墙钟。墙钟包含往返开销，
   四个性质不同的查询在墙钟下都是 24-27ms —— 差异被完全淹没。
3. 规模敏感性要跑多个量级。只测一个数据量看不出线性还是爆炸。

用法：
    python3 bench.py              # 跑全套
    python3 bench.py --quick      # 只跑基线 + 检索对比
"""
import sys
import os
import time
import statistics

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn, fmt_ms  # noqa: E402
from retrieve import Retriever  # noqa: E402

QUESTIONS = [
    "索引怎么加速查询",
    "权限怎么配置",
    "图遍历的边界在哪",
    "向量检索怎么做混合",
    "存储后端选哪个",
]

MODES = ["kw", "vec", "hybrid"]


def baseline(conn, n=7):
    """空操作基线：一条什么也不做的语句，纯 HTTP 往返成本。"""
    times = []
    for _ in range(n):
        ok, payload, err = conn.sql("RETURN 1;")
        if not ok:
            continue
        for item in payload:
            t = fmt_ms(item.get("time"))
            if t is not None:
                times.append(t)
    return times


def wall_clock(conn, question, mode, r, n=7):
    """客户端墙钟时间（用于与服务端自报时间对比，证明基线不可忽略）。"""
    ts = []
    for _ in range(n):
        t0 = time.time()
        r.search(question, mode=mode, limit=5)
        ts.append((time.time() - t0) * 1000)
    return ts


def med(xs):
    return statistics.median(xs) if xs else None


def main():
    quick = "--quick" in sys.argv
    conn = Conn()
    r = Retriever(conn, k=5)

    print("=" * 76)
    print("可观测 · 性能测量（SurrealDB 3.2.4 / docsqa）")
    print("=" * 76)

    print()
    print("【第 1 步】空操作基线 —— 不测这个，后面所有数字都无法解释")
    print("-" * 76)
    bl = baseline(conn)
    bl_med = med(bl)
    print("  RETURN 1;  服务端自报中位 %.3f ms  样本 %d 条" % (bl_med, len(bl)))
    print("  含义：这是单次请求的固定成本（解析 + 调度 + 返回），")
    print("        任何查询的实际耗时都应该在这个量级上叠加。")

    print()
    print("【第 2 步】三种检索模式的服务端自报耗时（中位，ms）")
    print("-" * 76)
    print("  %-22s %10s %10s %10s" % ("问题", "kw", "vec", "hybrid"))
    srv_rows = []
    for q in QUESTIONS:
        row = []
        for mode in MODES:
            rows, m, err = None, None, None
            try:
                from retrieve import measure
                rows, m, err = measure(conn, q, mode, k=5, repeat=5)
            except Exception as e:
                err = str(e)
            row.append(m)
        srv_rows.append((q, row))
        print("  %-22s %10s %10s %10s" % (
            q[:20],
            *[("%.2f" % v) if v is not None else "—" for v in row]))

    print()
    print("【第 3 步】客户端墙钟 vs 服务端自报 —— 证明为什么必须用服务端口径")
    print("-" * 76)
    print("  %-22s %12s %12s %10s" % ("问题", "墙钟ms", "服务端ms", "差值"))
    for q in QUESTIONS[:3]:
        w = med(wall_clock(conn, q, "hybrid", r))
        from retrieve import measure
        _, s, _ = measure(conn, q, "hybrid", k=5, repeat=5)
        if w is not None and s is not None:
            print("  %-22s %12.2f %12.2f %10.2f" % (q[:20], w, s, w - s))
        else:
            print("  %-22s %12s %12s" % (q[:20], w, s))
    print("  差值 ≈ HTTP 往返 + 客户端开销。若差值远大于服务端耗时，")
    print("  说明你测的是网络，不是数据库。")

    if quick:
        print()
        print("（--quick 模式，跳过规模敏感性测试）")
        return 0

    print()
    print("【第 4 步】规模敏感性：数据量翻倍，耗时怎么变？")
    print("-" * 76)
    print("  造一张临时表，分段灌入不同量级，看查询耗时曲线。")
    print("  %-12s %12s %12s %10s" % ("行数", "全表聚合ms", "带过滤ms", "实灌行数"))
    conn.sql("REMOVE TABLE IF EXISTS bench_scale;")
    conn.sql("DEFINE TABLE bench_scale SCHEMAFULL TYPE NORMAL; "
             "DEFINE FIELD v ON bench_scale TYPE number; "
             "DEFINE FIELD cat ON bench_scale TYPE string;")

    for n in [2000, 8000, 32000]:
        conn.sql("DELETE bench_scale;")
        # 批量写：课 12 实测逐行写与批量写差约 940 倍，这里必须批量
        # ⚠️ 3.2.4 没有 INSERT ... VALUES 语法（Parse error: Unexpected token
        #    `VALUES`）。用对象数组：INSERT INTO t [{...},{...}]
        #    （diag_scale.py 抓出：用 VALUES 时三档数据全是 0 行，
        #     "耗时不随数据量变化"是纯粹的假象。）
        batch = 1000
        done = 0
        while done < n:
            size = min(batch, n - done)
            rows = ",".join(
                "{id: bench_scale:s%d, v: %d, cat: 'c%d'}" % (done + i, i, i % 8)
                for i in range(size))
            ok, payload, err = conn.sql("INSERT INTO bench_scale [%s];" % rows)
            if not ok:
                print("  ✗ 灌数据失败：%s" % str(payload)[:200])
                break
            done += size

        # 断言行数：不断言就会得到"0 行也很快"的假结论
        ok, payload, err = conn.sql("SELECT count() FROM bench_scale GROUP ALL;")
        real = payload[-1]["result"][0]["count"] if ok else "?"
        if real != n:
            print("  ✗ 实灌 %s 行，期望 %d —— 数据没灌够，耗时数据无效" % (real, n))

        def timed(q, repeat=3):
            ts = []
            for _ in range(repeat):
                ok, payload, err = conn.sql(q)
                if not ok:
                    return None
                for item in payload:
                    t = fmt_ms(item.get("time"))
                    if t is not None:
                        ts.append(t)
            return med(ts)

        t_agg = timed("SELECT cat, count() FROM bench_scale GROUP BY cat;")
        t_filt = timed("SELECT v FROM bench_scale WHERE cat = 'c3' LIMIT 100;")
        print("  %-12d %12s %12s %10s" % (n,
                                          ("%.2f" % t_agg) if t_agg else "—",
                                          ("%.2f" % t_filt) if t_filt else "—",
                                          real))

    conn.sql("REMOVE TABLE IF EXISTS bench_scale;")
    print()
    print("  判读：耗时随数据量线性增长 = 可预测；")
    print("        某一档突然跳一个数量级 = 撞上了崩点（如索引失效、内存放不下）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
