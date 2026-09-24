#!/bin/bash
# 核验：A/B 的 await 是「逐条串行」而 C 是「并发线程池」？
# 若成立，则上一轮 IO 对照是【实验设计不公平】，不是库差异
# 正解：三方都用「批量并发 gather」重测
set -u
cat > /tmp/l11_fair.py <<'PYEOF'
import asyncio, time, json
from concurrent.futures import ThreadPoolExecutor
BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"; TOPIC="l11-async-bench"
N=3000; IO_WAIT=0.0005; BATCH=100

def banner(t): print(f"\n{'─'*74}\n{t}\n{'─'*74}")

# ---- A 串行 await（上一轮写法）----
async def a_serial():
    t0=time.perf_counter()
    for _ in range(N): await asyncio.sleep(IO_WAIT)
    return time.perf_counter()-t0

# ---- A 并发 gather（公平写法）----
async def a_gather():
    t0=time.perf_counter()
    for s in range(0,N,BATCH):
        n=min(BATCH,N-s)
        await asyncio.gather(*[asyncio.sleep(IO_WAIT) for _ in range(n)])
    return time.perf_counter()-t0

# ---- B 并发（AIOConsumer 批处理 + gather）----
async def b_gather():
    t0=time.perf_counter()
    for s in range(0,N,BATCH):
        n=min(BATCH,N-s)
        await asyncio.gather(*[asyncio.sleep(IO_WAIT) for _ in range(n)])
    return time.perf_counter()-t0

# ---- C 线程池并发 ----
def c_pool():
    t0=time.perf_counter()
    with ThreadPoolExecutor(max_workers=8) as ex:
        for s in range(0,N,BATCH):
            n=min(BATCH,N-s)
            for f in [ex.submit(time.sleep,IO_WAIT) for _ in range(n)]: f.result()
    return time.perf_counter()-t0

async def main():
    print("="*74); print("核验：上一轮 IO 对照是否公平"); print("="*74)
    print(f"  N={N}  IO={IO_WAIT*1000:.1f}ms/条  批次={BATCH}")
    print(f"  理论下限（全并发）: {N*IO_WAIT/BATCH:.3f}s")
    print(f"  理论上限（全串行）: {N*IO_WAIT:.3f}s\n")
    s=await a_serial(); g=await a_gather(); c=c_pool()
    print(f"  A 逐条串行 await : {s:7.3f}s  {N/s:9.1f} msg/s   <- 上一轮 A 的写法")
    print(f"  A 批量 gather    : {g:7.3f}s  {N/g:9.1f} msg/s   <- 公平写法")
    print(f"  C 线程池(8 workers): {c:7.3f}s  {N/c:9.1f} msg/s")
    print(f"\n  串行/并发比: {s/g:.2f}x")
    print(f"\n  判定：若 s/g 接近 {BATCH} -> 上一轮确实是【逐条串行 vs 并发】的不公平对照")
    print(f"        -> 差的不是库，是写法。必须重测。")

asyncio.run(main())
PYEOF
docker cp /tmp/l11_fair.py l11-build:/fair.py >/dev/null
docker exec l11-build /app/.venv/bin/python /fair.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -30
