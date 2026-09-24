#!/bin/bash
# 核验2：锁定 1.06x 的真正原因 —— 是不是没传 chunksize？
# models 脚本: ex.map(fn, items)              -> 默认 chunksize=1
# diag  脚本: ex.map(fn, items, chunksize=N)  -> 批量派发
# 其他条件全部固定，只变 chunksize
set -u
cat > /tmp/l10_cs.py <<'PYEOF'
import time
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor

def process_msg(i):
    s = 0
    for k in range(6000): s += k*k
    return s

M = 2000
items = list(range(M))
print("=" * 70)
print("核验2：chunksize 是不是 1.06x 的真凶")
print("=" * 70)
print(f"M={M}, 每 task 6000 次乘加，4 进程\n")

t0=time.perf_counter()
for i in items: process_msg(i)
ser = time.perf_counter()-t0
print(f"  串行基线            : {ser:.2f}s  ({M/ser:,.0f}/s)")

for w in [4]:
    for cs in [1, 10, 50, 125, 500]:
        t0=time.perf_counter()
        with ProcessPoolExecutor(max_workers=w) as ex:
            list(ex.map(process_msg, items, chunksize=cs))
        el = time.perf_counter()-t0
        print(f"  {w} 进程 chunksize={cs:<5}: {el:.2f}s  加速比 {ser/el:.2f}x")

print(f"\n判定:")
print(f"  chunksize=1（默认值，models 脚本用的）若明显慢 -> 确认是 IPC 次数问题")
print(f"  ⚠ ProcessPoolExecutor.map 默认 chunksize=1，")
print(f"     即每条消息一次 IPC —— 这是极易踩的默认值陷阱")
print("=" * 70)
PYEOF
docker run --rm -v /tmp/l10_cs.py:/c.py --network bench_kafka-net \
  kafka-pybench:3.12 /app/.venv/bin/python /c.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -25
