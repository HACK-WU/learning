"""E2+E3：选择器写法对成本的影响 —— 无界正则 vs 精确匹配。

四种写法，命中同样的序列，比较成本：
  1. 精确等值      l6_card_metric{idx="000123"}
  2. 前缀正则      l6_card_metric{idx=~"000123.*"}   （有界：有字面前缀）
  3. 无界正则      l6_card_metric{idx=~".*123"}     （无界：.* 开头）
  4. 全匹配正则    l6_card_metric{idx=~".+"}        （最坏：命中全部）

关键教学点：正则是否有**字面前缀**，决定能否用倒排索引裁剪。
"""
import statistics
import time

from l6lib import app_get, query, query_range, now


def bench(expr, start, end, step, n=7):
    els, pts, nser = [], [], []
    for _ in range(n):
        t0 = time.perf_counter()
        r = query_range(expr, start, end, step)
        els.append((time.perf_counter() - t0) * 1000)
        if r:
            pts.append(sum(len(x["values"]) for x in r))
            nser.append(len(r))
    return (statistics.median(els), min(els), max(els),
            int(statistics.median(pts or [0])), int(statistics.median(nser or [0])))


print("== 准备：20000 条序列 ==")
print(app_get("/cardinality?n=20000"))
time.sleep(10)
end = now()

cases = [
    ('l6_card_metric{idx="000123"}', "精确等值", "命中 1 条"),
    ('l6_card_metric{idx=~"000123.*"}', "有界正则(字面前缀)", "命中 1 条"),
    ('l6_card_metric{idx=~".*123"}', "无界正则(.* 开头)", "命中多条"),
    ('l6_card_metric{idx=~".+"}', "全匹配正则", "命中 20000 条"),
    ('{__name__=~".+"}', "最坏：全局无界", "命中全部序列"),
]

print()
print("== 选择器写法对照（时间窗 5m / step 15s） ==")
print(f'{"写法":<22} | {"说明":<16} | {"命中":>7} | {"点数":>7} | {"中位(ms)":>9} | {"min~max":>16}')
print("-" * 96)
for expr, label, note in cases:
    m, lo, hi, pts, ns = bench(expr, end - 300, end, "15s")
    print(f"{label:<22} | {note:<16} | {ns:>7} | {pts:>7} | {m:>9.1f} | {lo:>7.1f}~{hi:<7.1f}")

print()
print("== 补充：命中相同序列数时，正则 vs 等值的纯开销 ==")
# 精确控制：都只命中 1 条
for expr, label in [
    ('l6_card_metric{idx="000123"}', "等值"),
    ('l6_card_metric{idx=~"000123"}', "正则但无元字符"),
    ('l6_card_metric{idx=~"00012[3]"}', "正则含字符类"),
    ('l6_card_metric{idx=~".*000123"}', "无界正则 .* 前缀"),
]:
    els = []
    for _ in range(7):
        t0 = time.perf_counter()
        query(expr)
        els.append((time.perf_counter() - t0) * 1000)
    nhit = len(query(expr) or [])
    print(f"   {label:<22} 命中={nhit:<3} 中位={statistics.median(els):>7.1f}ms "
          f"({min(els):.1f}~{max(els):.1f})")
