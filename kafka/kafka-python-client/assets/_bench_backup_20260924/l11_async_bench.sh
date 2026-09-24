#!/bin/bash
# 课 11 正测：三方「公平」对照 —— 三方都用批量并发处理
# 修正：上一轮 A/B 逐条 await（串行）vs C 线程池（并发），不公平，差 70x
set -u
cat > /tmp/l11_final.py <<'PYEOF'
import asyncio, time, json, statistics
from concurrent.futures import ThreadPoolExecutor
from confluent_kafka import Producer as SyncProducer
from confluent_kafka.aio import AIOConsumer

BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"; TOPIC="l11-async-bench"
N=3000; CPU=3000; IO_WAIT=0.0005; BATCH=100; REPEAT=5

def cpu_task(n=CPU):
    s=0
    for i in range(n): s+=i*3
    return s
def io_task(): time.sleep(IO_WAIT)

def seed():
    p=SyncProducer({"bootstrap.servers":BROKERS})
    for i in range(N): p.produce(TOPIC, json.dumps({"i":i,"pad":"x"*200}).encode())
    p.flush()

def banner(t): print(f"\n{'─'*74}\n{t}\n{'─'*74}")

# ══ A: aiokafka + gather 并发 ══
async def run_aiokafka(mode):
    from aiokafka import AIOKafkaConsumer
    gid=f"l11-f-a-{mode}-{int(time.time()*1000)%100000}"
    c=AIOKafkaConsumer(TOPIC,bootstrap_servers=BROKERS,group_id=gid,
                       auto_offset_reset="earliest",enable_auto_commit=False)
    await c.start()
    t0=time.perf_counter(); got=0
    try:
        while got<N:
            batch=await c.getmany(timeout_ms=1000,max_records=BATCH)
            items=[m for tp in batch.values() for m in tp]
            if not items: 
                if got>0: break
                continue
            if mode=="cpu": [cpu_task() for _ in items]          # CPU 只能串行（GIL）
            else: await asyncio.gather(*[asyncio.sleep(IO_WAIT) for _ in items])
            got+=len(items)
        return time.perf_counter()-t0, got
    finally: await c.stop()

# ══ B: AIOConsumer + gather 并发 ══
async def run_aio_consumer(mode):
    gid=f"l11-f-b-{mode}-{int(time.time()*1000)%100000}"
    c=AIOConsumer({"bootstrap.servers":BROKERS,"group.id":gid,
                   "auto.offset.reset":"earliest","enable.auto.commit":False})
    await c.subscribe([TOPIC])
    t0=time.perf_counter(); got=0
    try:
        while got<N:
            msgs=await c.consume(num_messages=BATCH,timeout=1.0)
            items=[m for m in msgs if not m.error()]
            if not items:
                if got>0: break
                continue
            if mode=="cpu": [cpu_task() for _ in items]
            else: await asyncio.gather(*[asyncio.sleep(IO_WAIT) for _ in items])
            got+=len(items)
        return time.perf_counter()-t0, got
    finally: await c.close()

# ══ C: 同步 Consumer + 线程池并发 ══
def run_threadpool(mode):
    from confluent_kafka import Consumer
    gid=f"l11-f-c-{mode}-{int(time.time()*1000)%100000}"
    c=Consumer({"bootstrap.servers":BROKERS,"group.id":gid,
                "auto.offset.reset":"earliest","enable.auto.commit":False})
    c.subscribe([TOPIC]); t0=time.perf_counter(); got=0
    ex=ThreadPoolExecutor(max_workers=8)
    try:
        while got<N:
            msgs=c.consume(num_messages=BATCH,timeout=1.0)
            items=[m for m in msgs if not m.error()]
            if not items:
                if got>0: break
                continue
            futs=[ex.submit(cpu_task if mode=="cpu" else io_task) for _ in items]
            for f in futs: f.result()
            got+=len(items)
        return time.perf_counter()-t0, got
    finally: c.close(); ex.shutdown()

async def amain():
    print("="*74)
    print("课 11 · 三方公平对照（均为批量并发，REPEAT=%d 取中位）"%REPEAT)
    print(f"  N={N}  CPU乘加={CPU}/条  IO={IO_WAIT*1000:.1f}ms/条  批次={BATCH}")
    print("="*74)
    seed()
    for mode in ["cpu","io"]:
        banner(f"场景：{'纯 CPU 密集' if mode=='cpu' else f'含 {IO_WAIT*1000:.1f}ms IO'}")
        res={}
        for name,fn,is_async in [("A aiokafka",run_aiokafka,True),
                                  ("B AIOConsumer",run_aio_consumer,True),
                                  ("C 同步+线程池",run_threadpool,False)]:
            ts=[]
            for r in range(REPEAT):
                try:
                    el,got=(await fn(mode)) if is_async else fn(mode)
                    if got>=N*0.95: ts.append(el)
                except Exception as e: print(f"    round{r} {name}: {type(e).__name__}: {str(e)[:40]}")
            if ts:
                lo,md,hi=min(ts),statistics.median(ts),max(ts)
                res[name]=md
                print(f"  {name:<16} 中位 {md:6.3f}s  区间[{lo:.3f}, {hi:.3f}]  {N/md:8.0f} msg/s")
            else: print(f"  {name:<16} ✗ 全部失败")
        if len(res)==3:
            base=res["C 同步+线程池"]
            print(f"\n  相对 C 基线(线程池):")
            for k,v in res.items(): print(f"    {k:<16} {base/v:5.2f}x")

asyncio.run(amain())
PYEOF
docker cp /tmp/l11_final.py l11-build:/final.py >/dev/null
docker exec l11-build /app/.venv/bin/python /final.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -40
