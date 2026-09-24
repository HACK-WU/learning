#!/bin/bash
# 核验：为什么纯 CPU 密集的进程池只加速 1.06x，而探路脚本里是 3.54x？
# 假设1: 每个 task 太小，进程间 IPC 开销吃掉收益
# 假设2: 2000 个 task 分 4 进程 = 每进程 500 次 map 调用，调度开销大
# 假设3: 进程启动本身就贵（fork 20核环境）
# 验证：增大单 task 粒度 + 用 chunksize 减少 IPC 次数
set -u
cat > /tmp/l10_diag.py <<'PYEOF'
import time, os
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor

def burn(n):
    s = 0
    for i in range(n): s += i*i
    return s

print("=" * 72)
print("核验：进程池为何只有 1.06x")
print("=" * 72)

# 固定总工作量，改变「单 task 粒度」
TOTAL = 12_000_000

print(f"\n总工作量固定 {TOTAL:,}，改变单 task 粒度：\n")
print(f"  {'每task量':<14}{'task数':<9}{'串行':<10}{'4进程':<10}{'加速比'}")
print(f"  {'-'*54}")

for per, ntasks in [(6000, 2000), (60_000, 200), (600_000, 20), (3_000_000, 4)]:
    total = per * ntasks
    t0=time.perf_counter()
    for _ in range(ntasks): burn(per)
    ser = time.perf_counter()-t0

    chunks = max(1, ntasks // 4)
    t0=time.perf_counter()
    with ProcessPoolExecutor(max_workers=4) as ex:
        list(ex.map(burn, [per]*ntasks, chunksize=chunks))
    par = time.perf_counter()-t0
    print(f"  {per:<14,}{ntasks:<9}{ser:<10.2f}{par:<10.2f}{ser/par:>8.2f}x")

print(f"\n结论判读:")
print(f"  · 单 task 越小 -> IPC/调度开销占比越高 -> 进程加速比越低")
print(f"  · 讲义若用 6000/task 的粒度，会得出『进程没用』的错误结论")
print(f"  · 这本身就是一条工程教训：并发粒度决定成败")

# 进程启动成本
print(f"\n附带：进程池启动成本")
for w in [2, 4]:
    t0=time.perf_counter()
    with ProcessPoolExecutor(max_workers=w) as ex:
        list(ex.map(burn, [10]*w))
    print(f"  {w} worker 启动+空跑: {(time.perf_counter()-t0)*1000:.0f} ms")
print("=" * 72)
PYEOF
docker run --rm -v /tmp/l10_diag.py:/d.py --network bench_kafka-net \
  kafka-pybench:3.12 /app/.venv/bin/python /d.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -30
