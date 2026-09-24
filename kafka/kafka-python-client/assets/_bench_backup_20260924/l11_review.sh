#!/bin/bash
# 课 11 独立复审：逐条核验讲义结论（不自信，只信实测输出）
set -u
cat > /tmp/l11_review.py <<'PYEOF'
import inspect, threading, asyncio, time, json, statistics
from concurrent.futures import ThreadPoolExecutor
P=F=0
def chk(desc, cond, ev=""):
    global P,F
    if cond: P+=1; print(f"  ✓ {desc}")
    else: F+=1; print(f"  ✗ {desc}   <<< 证据: {ev}")

print("="*74); print("课 11 独立复审：讲义结论逐条核验"); print("="*74)

# ── 结论1: AIOConsumer 在子模块，顶层查不到 ──
import confluent_kafka as ck
chk("结论1a 顶层 hasattr(AIOConsumer)==False", not hasattr(ck,"AIOConsumer"),
    f"实际={hasattr(ck,'AIOConsumer')}")
try:
    from confluent_kafka.aio import AIOConsumer, AIOProducer
    chk("结论1b 子模块可 import", True)
except ImportError as e:
    chk("结论1b 子模块可 import", False, str(e))

# ── 结论2: ThreadPoolExecutor 包装 ──
src=inspect.getsource(AIOConsumer.__init__)
chk("结论2a __init__ 含 ThreadPoolExecutor", "ThreadPoolExecutor" in src)
chk("结论2b 默认 max_workers==2", "max_workers: int = 2" in src, src[:200])
csrc=inspect.getsource(AIOConsumer.consume) if hasattr(AIOConsumer,'consume') else ""
chk("结论2c consume 内部走 executor", "_call" in csrc or "executor" in csrc.lower())

# ── 结论3: 同步上下文构造抛 RuntimeError ──
try:
    AIOConsumer({"bootstrap.servers":"kafka-1:9092","group.id":"rv"})
    chk("结论3 同步构造抛 RuntimeError", False, "没抛异常")
except RuntimeError as e:
    chk("结论3 同步构造抛 RuntimeError", "no running event loop" in str(e), str(e))
except Exception as e:
    chk("结论3 同步构造抛 RuntimeError", False, f"{type(e).__name__}: {e}")

# ── 结论6: async 端点调同步阻塞 -> 事件循环冻结 ──
async def loop_test():
    ticks={"n":0}
    async def hb():
        while True:
            ticks["n"]+=1; await asyncio.sleep(0.01)
    t=asyncio.create_task(hb()); await asyncio.sleep(0.05)
    b=ticks["n"]; time.sleep(0.5); blocked=ticks["n"]-b
    t.cancel()
    ticks["n"]=0
    t2=asyncio.create_task(hb()); await asyncio.sleep(0.05)
    b2=ticks["n"]
    await asyncio.get_running_loop().run_in_executor(None, time.sleep, 0.5)
    nonblock=ticks["n"]-b2
    t2.cancel()
    return blocked, nonblock
blocked, nonblock = asyncio.run(loop_test())
chk("结论6a 同步阻塞期间心跳==0", blocked==0, f"实际={blocked}")
chk("结论6b run_in_executor 期间心跳~49", nonblock>=40, f"实际={nonblock}")

# ── 坑3: lifespan 必须用 asynccontextmanager ──
from fastapi import FastAPI
try:
    async def bare_lifespan(app):
        yield
    app=FastAPI(); app.router.lifespan_context=bare_lifespan
    from fastapi.testclient import TestClient
    with TestClient(app) as c: pass
    chk("坑3 裸 async_generator 会报错", False, "居然没报错")
except TypeError as e:
    chk("坑3 裸 async_generator 会报错", "asynchronous context manager" in str(e), str(e))
except Exception as e:
    chk("坑3 裸 async_generator 会报错", False, f"{type(e).__name__}: {e}")

# ── 结论4/5 数据是否自洽（区间不重叠 + 中位关系）──
cpu={"A":0.258,"B":0.435,"C":0.462}
io ={"A":0.059,"B":0.235,"C":0.430}
chk("结论4 CPU场景 A最快", cpu["A"]<cpu["B"]<cpu["C"], str(cpu))
chk("结论5a IO场景 A最快", io["A"]<io["B"]<io["C"], str(io))
chk("结论5b IO场景 A 相对C ≥7x", io["C"]/io["A"]>=7.0, f"实际={io['C']/io['A']:.2f}x")
chk("结论5c B 在IO场景 ≥1.5x", io["C"]/io["B"]>=1.5, f"实际={io['C']/io['B']:.2f}x")
chk("结论4b A CPU加速比 <2x（async对CPU无大用）", cpu["C"]/cpu["A"]<2.0,
    f"实际={cpu['C']/cpu['A']:.2f}x")

print("\n"+"="*74)
print(f"  通过 {P}  失败 {F}")
print("="*74)
print("\n【复审员补充质疑】")
print("  1. 讲义表格 CPU 场景 A∈[0.258,0.280] 与 C∈[0.425,0.502] 不重叠 ✓")
print("     但 B∈[0.428,0.448] 与 C∈[0.425,0.502] 【重叠】->")
print("     讲义称 B 为 1.06x，需标注『B 与 C 在 CPU 场景无显著差异』")
print("  2. AIOConsumer 默认 max_workers=2，讲义未测调大后的表现，属已知边界")
PYEOF
docker cp /tmp/l11_review.py l11-build:/rv.py >/dev/null
docker exec l11-build /app/.venv/bin/python /rv.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' -e Starlette -e 'from starlette' | head -40
