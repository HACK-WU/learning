#!/bin/bash
# 课 10 探路：并发环境基线
set -u
cat > /tmp/l10_probe.py <<'PYEOF'
import os, sys, sysconfig, multiprocessing as mp, time
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor

print("=== 1. CPU 与 GIL ===")
print(f"  os.cpu_count()          : {os.cpu_count()}")
print(f"  len(os.sched_getaffinity): {len(os.sched_getaffinity(0))}")
print(f"  mp.cpu_count()          : {mp.cpu_count()}")
print(f"  sysconfig GIL disabled  : {sysconfig.get_config_var('Py_GIL_DISABLED')}")
print(f"  sys._is_gil_enabled()   : {getattr(sys,'_is_gil_enabled',lambda:'N/A')()}")
print(f"  Python                  : {sys.version.split()[0]}")

# 实测 GIL 是否真锁：CPU 密集任务线程 vs 进程
def cpu_burn(n):
    s = 0
    for i in range(n): s += i*i
    return s

N = 12_000_000
print(f"\n=== 2. GIL 实测：CPU 密集 N={N:,} ===")
t0=time.perf_counter(); cpu_burn(N); t1=time.perf_counter()
serial = t1-t0
print(f"  串行 1 份            : {serial:.2f}s")

t0=time.perf_counter()
with ThreadPoolExecutor(max_workers=4) as ex:
    list(ex.map(cpu_burn, [N//4]*4))
tthread=time.perf_counter()-t0
print(f"  4 线程（各 1/4 量）   : {tthread:.2f}s   加速比 {serial/tthread:.2f}x")

# 进程池在容器内可能受限，先试
try:
    t0=time.perf_counter()
    with ProcessPoolExecutor(max_workers=4) as ex:
        list(ex.map(cpu_burn, [N//4]*4))
    tproc=time.perf_counter()-t0
    print(f"  4 进程（各 1/4 量）   : {tproc:.2f}s   加速比 {serial/tproc:.2f}x")
    print(f"  -> 线程/进程 加速比对比: 线程 {serial/tthread:.2f}x vs 进程 {serial/tproc:.2f}x")
except Exception as e:
    print(f"  ✗ 进程池失败: {type(e).__name__}: {str(e)[:100]}")

print(f"\n=== 3. 进程启动方式 ===")
print(f"  mp.get_start_method()   : {mp.get_start_method()}")
print(f"  可用方法                : {mp.get_all_start_methods()}")
PYEOF
docker run --rm -v /tmp/l10_probe.py:/p.py --network bench_kafka-net \
  kafka-pybench:3.12 /app/.venv/bin/python /p.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -30
