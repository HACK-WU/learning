#!/bin/bash
# 课 11 收官实验：FastAPI 并发请求下，async 生产者到底值不值
# 单请求看不出差别；并发才是 async 的意义所在
set -u
cat > /tmp/l11_conc.py <<'PYEOF'
import asyncio, time, json, statistics
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.testclient import TestClient
import threading
BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"; TOPIC="l11-async-bench"
CONC=30; PER=20      # 30 并发 x 每条发 20 条消息

def banner(t): print(f"\n{'─'*74}\n{t}\n{'─'*74}")

# ── X: async 端点 + aiokafka（真 async）──
def build_async_app():
    from aiokafka import AIOKafkaProducer
    prod={"p":None}
    @asynccontextmanager
    async def lifespan(app):
        p=AIOKafkaProducer(bootstrap_servers=BROKERS); await p.start(); prod["p"]=p
        yield
        await p.stop()
    app=FastAPI(lifespan=lifespan)
    @app.get("/send/{n}")
    async def send(n:int):
        for i in range(n): await prod["p"].send(TOPIC, json.dumps({"a":i}).encode())
        return {"sent":n}
    return app

# ── Y: sync 端点（def 而非 async def -> FastAPI 自动丢线程池）──
def build_sync_app():
    from confluent_kafka import Producer
    prod={"p":None}
    @asynccontextmanager
    async def lifespan(app):
        prod["p"]=Producer({"bootstrap.servers":BROKERS})
        yield
        prod["p"].flush()
    app=FastAPI(lifespan=lifespan)
    @app.get("/send/{n}")
    def send(n:int):                       # 注意：def，不是 async def
        for i in range(n): prod["p"].produce(TOPIC, json.dumps({"a":i}).encode())
        prod["p"].flush()
        return {"sent":n}
    return app

def drive(app,label):
    from concurrent.futures import ThreadPoolExecutor
    with TestClient(app) as cl:
        cl.get("/health") if label=="X" else None
        def one(_): 
            r=cl.get(f"/send/{PER}"); return r.status_code
        t0=time.perf_counter()
        with ThreadPoolExecutor(max_workers=CONC) as ex:
            codes=list(ex.map(one,range(CONC)))
        el=time.perf_counter()-t0
    ok=codes.count(200)
    print(f"  {label}: {el:6.3f}s   成功 {ok}/{CONC}   {CONC*PER/el:8.0f} msg/s")
    return el

print("="*74)
print(f"课 11 · FastAPI 并发请求实测（{CONC} 并发 × {PER} 条/请求）")
print("="*74)
banner("X = async def + aiokafka    Y = def（同步，FastAPI 自动线程池）")
xs=[];ys=[]
for r in range(3):
    try: xs.append(drive(build_async_app(),"X"))
    except Exception as e: print(f"  X round{r}: {type(e).__name__}: {str(e)[:50]}")
    try: ys.append(drive(build_sync_app(),"Y"))
    except Exception as e: print(f"  Y round{r}: {type(e).__name__}: {str(e)[:50]}")
if xs and ys:
    print(f"\n  X 中位 {statistics.median(xs):.3f}s   区间[{min(xs):.3f},{max(xs):.3f}]")
    print(f"  Y 中位 {statistics.median(ys):.3f}s   区间[{min(ys):.3f},{max(ys):.3f}]")
    print(f"  X/Y 提速比: {statistics.median(ys)/statistics.median(xs):.2f}x")
PYEOF
docker cp /tmp/l11_conc.py l11-build:/conc.py >/dev/null
docker exec l11-build /app/.venv/bin/python /conc.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' -e Starlette -e 'from starlette' | head -25
