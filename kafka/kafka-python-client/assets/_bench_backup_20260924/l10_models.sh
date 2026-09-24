#!/bin/bash
# 课 10 实验①：消费端并发模型 —— 处理侧吞吐对照
#
# 核心问题：消费慢，加线程有用还是必须加进程？
# 解法：把「拉取」和「处理」拆开测。处理侧用可控的 CPU 负载模拟真实业务。
set -u
cat > /tmp/l10_models.py <<'PYEOF'
import os, sys, time, multiprocessing as mp
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor

print("=" * 76)
print("课 10 · 消费端并发模型对照（处理侧）")
print("=" * 76)

# 模拟每条消息的业务处理：一半 CPU 密集（解析/计算），一半 sleep（模拟 IO）
def process_msg(i):
    s = 0
    for k in range(6000): s += k * k          # CPU 密集部分
    return s

def process_with_io(i):
    s = process_msg(i)
    time.sleep(0.0002)                         # 模拟 IO 等待
    return s

M = 2000   # 消息条数（下调：8 进程 fork 曾把 WSL 打满导致连接中断）

def run(name, fn, items, pool_factory, workers):
    """⚠ chunksize 必须显式给：ProcessPoolExecutor.map 默认 chunksize=1，
       实测会让 4 进程退化到 0.71x（比串行还慢）——见 l10_diag_chunksize2.sh"""
    t0 = time.perf_counter()
    cs = max(1, len(items) // workers // 4) if pool_factory is ProcessPoolExecutor else 1
    try:
        with pool_factory(max_workers=workers) as ex:
            list(ex.map(fn, items, chunksize=cs))
        el = time.perf_counter() - t0
        return M / el, el
    except Exception as e:
        return None, f"{type(e).__name__}: {str(e)[:60]}"

items = list(range(M))

print(f"\n消息数 M={M},  每条约 6000 次乘加（CPU 密集）+ 0.2ms IO 等待\n")

scenarios = [
    ("A. CPU 密集", process_msg),
    ("B. CPU + IO 混合", process_with_io),
]

for sname, fn in scenarios:
    print(f"────── {sname} ──────")
    print(f"  {'模型':<22}{'worker':<9}{'吞吐/s':>14}{'加速比':>10}")
    print(f"  {'-'*54}")

    t0=time.perf_counter()
    for i in items: fn(i)
    base_el = time.perf_counter()-t0
    base = M/base_el
    print(f"  {'串行（基线）':<22}{'1':<9}{base:>14,.0f}{'1.00x':>10}")

    results = {}
    for label, factory, w in [
        ("线程", ThreadPoolExecutor, 2),
        ("线程", ThreadPoolExecutor, 4),
        ("进程", ProcessPoolExecutor, 2),
        ("进程", ProcessPoolExecutor, 4),
    ]:
        tp, el = run(label, fn, items, factory, w)
        if tp is None:
            print(f"  {label+' x'+str(w):<22}{w:<9}{'失败':>14}   {el}")
        else:
            results[f"{label}{w}"] = tp
            print(f"  {label+' x'+str(w):<22}{w:<9}{tp:>14,.0f}{tp/base:>9.2f}x")
    print()

print("=" * 76)
print("判读")
print("=" * 76)
print("  · 线程加速比接近 1.00x  -> GIL 锁死，加线程白加")
print("  · 进程加速比接近核数    -> 真并行，加进程有效")
print("  · 『CPU+IO 混合』比纯 CPU 时线程收益高 -> IO 等待期间会释放 GIL")
print("=" * 76)
PYEOF
docker run --rm -v /tmp/l10_models.py:/m.py --network bench_kafka-net \
  kafka-pybench:3.12 /app/.venv/bin/python /m.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -40
