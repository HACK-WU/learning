#!/bin/bash
# 复审补充：1) B vs C 在 CPU 场景是否真有差异  2) max_workers 调大的影响
set -u
cat > /tmp/l11_mw.py <<'PYEOF'
import asyncio, time, json, statistics
from concurrent.futures import ThreadPoolExecutor
from confluent_kafka import Producer as SyncProducer
from confluent_kafka.aio import AIOConsumer
BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"; TOPIC="l11-async-bench"
N=3000; IO=0.0005; BATCH=100; REPEAT=5
def io_task(): time.sleep(IO)

async def run_b(mw, mode="io"):
    gid=f"l11-mw-{mw}-{int(time.time()*1000)%100000}"
    c=AIOConsumer({"bootstrap.servers":BROKERS,"group.id":gid,
                   "auto.offset.reset":"earliest","enable.auto.commit":False},
                  max_workers=mw)
    await c.subscribe([TOPIC]); t0=time.perf_counter(); got=0
    try:
        while got<N:
            msgs=await c.consume(num_messages=BATCH,timeout=1.0)
            items=[m for m in msgs if not m.error()]
            if not items:
                if got>0: break
                continue
            await asyncio.gather(*[asyncio.sleep(IO) for _ in items])
            got+=len(items)
        return time.perf_counter()-t0
    finally: await c.close()

def run_c(w, mode="io"):
    from confluent_kafka import Consumer
    gid=f"l11-mwc-{w}-{int(time.time()*1000)%100000}"
    c=Consumer({"bootstrap.servers":BROKERS,"group.id":gid,
                "auto.offset.reset":"earliest","enable.auto.commit":False})
    c.subscribe([TOPIC]); t0=time.perf_counter(); got=0
    ex=ThreadPoolExecutor(max_workers=w)
    try:
        while got<N:
            msgs=c.consume(num_messages=BATCH,timeout=1.0)
            items=[m for m in msgs if not m.error()]
            if not items:
                if got>0: break
                continue
            futs=[ex.submit(io_task) for _ in items]
            for f in futs: f.result()
            got+=len(items)
        return time.perf_counter()-t0
    finally: c.close(); ex.shutdown()

async def main():
    print("="*74)
    print("复审补充：AIOConsumer max_workers 影响（IO 场景，REPEAT=%d）"%REPEAT)
    print("="*74)
    p=SyncProducer({"bootstrap.servers":BROKERS})
    for i in range(N): p.produce(TOPIC, json.dumps({"i":i}).encode())
    p.flush()
    res={}
    for mw in [2,4,8,16]:
        ts=[]
        for _ in range(REPEAT):
            try: ts.append(await run_b(mw))
            except Exception as e: print(f"  mw={mw}: {type(e).__name__}: {str(e)[:40]}")
        if ts:
            res[mw]=statistics.median(ts)
            print(f"  max_workers={mw:<3} 中位 {statistics.median(ts):.3f}s  区间[{min(ts):.3f},{max(ts):.3f}]  {N/statistics.median(ts):7.0f} msg/s")
    for w in [8]:
        ts=[]
        for _ in range(REPEAT):
            try: ts.append(run_c(w))
            except Exception as e: pass
        if ts: res["C8"]=statistics.median(ts)
        print(f"  C 线程池(8)  中位 {statistics.median(ts):.3f}s  区间[{min(ts):.3f},{max(ts):.3f}]  {N/statistics.median(ts):7.0f} msg/s")
    print(f"\n  基线对照：aiokafka IO 场景 0.059s（讲义正测值）")
    if 2 in res:
        print(f"  max_workers 2 -> 16 提升: {res[2]/res.get(16,res[2]):.2f}x" if 16 in res else "")

asyncio.run(main())
PYEOF
docker cp /tmp/l11_mw.py l11-build:/mw.py >/dev/null
docker exec l11-build /app/.venv/bin/python /mw.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -25
