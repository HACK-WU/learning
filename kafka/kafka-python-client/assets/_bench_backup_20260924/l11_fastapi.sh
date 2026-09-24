#!/bin/bash
# 课 11 场景层：FastAPI 集成实测
# 验证两件事：
#   1. 同步 Consumer 塞进 FastAPI 会不会阻塞事件循环（async def 里调阻塞）
#   2. aiokafka / AIOConsumer 在 lifespan 里的正确挂载方式
set -u
cat > /tmp/l11_api.py <<'PYEOF'
import asyncio, time, threading, json, inspect
BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"; TOPIC="l11-async-bench"

def banner(t): print(f"\n{'─'*74}\n{t}\n{'─'*74}")

# ═══ 1. 阻塞事件循环实测：async def 里调同步阻塞调用 ═══
async def loop_block_demo():
    print("  场景：FastAPI 里 async def 端点调了同步阻塞 Kafka 调用")
    # 模拟：事件循环同时跑一个"心跳"协程 + 一个阻塞调用
    ticks={"n":0}
    async def heartbeat():
        while True:
            ticks["n"]+=1
            await asyncio.sleep(0.01)
    hb=asyncio.create_task(heartbeat())
    await asyncio.sleep(0.05)
    base=ticks["n"]
    t0=time.perf_counter()
    time.sleep(0.5)                      # 同步阻塞（模拟 c.consume 阻塞）
    blocked=time.perf_counter()-t0
    during=ticks["n"]-base
    await asyncio.sleep(0.05)
    hb.cancel()
    print(f"    阻塞 {blocked:.3f}s 期间，心跳协程只跑了 {during} 次（预期 ~{int(0.5/0.01)} 次）")
    print(f"    -> 整个事件循环被冻结，其他请求全部排队")
    # 对照：run_in_executor
    ticks["n"]=0
    hb2=asyncio.create_task(heartbeat())
    await asyncio.sleep(0.05)
    base2=ticks["n"]
    t0=time.perf_counter()
    await asyncio.get_running_loop().run_in_executor(None, time.sleep, 0.5)
    blocked2=time.perf_counter()-t0
    during2=ticks["n"]-base2
    await asyncio.sleep(0.05); hb2.cancel()
    print(f"    改用 run_in_executor：阻塞 {blocked2:.3f}s 期间心跳跑了 {during2} 次")
    print(f"    -> 事件循环存活，其他请求正常处理")
    return during, during2

# ═══ 2. 真实 FastAPI 服务 + aiokafka 生产者 ═══
def fastapi_demo():
    from contextlib import asynccontextmanager
    from fastapi import FastAPI
    from aiokafka import AIOKafkaProducer
    prod={"p":None}
    @asynccontextmanager
    async def lifespan(app):
        p=AIOKafkaProducer(bootstrap_servers=BROKERS)
        await p.start(); prod["p"]=p
        yield
        await p.stop()
    app=FastAPI(lifespan=lifespan)
    @app.get("/send/{n}")
    async def send(n:int):
        for i in range(n):
            await prod["p"].send(TOPIC, json.dumps({"api":i}).encode())
        return {"sent":n}
    @app.get("/health")
    async def health(): return {"ok":True}
    return app

async def main():
    print("="*74); print("课 11 · FastAPI 场景层实测"); print("="*74)
    banner("1. 事件循环阻塞：async def 里调同步阻塞调用")
    d1,d2=await loop_block_demo()
    print(f"\n  结论：阻塞/非阻塞 心跳次数比 = {d1}/{d2}")
    print(f"        -> async 端点里绝不能调同步 block 调用")

    banner("2. FastAPI + aiokafka 真实收发")
    try:
        from fastapi.testclient import TestClient
        app=fastapi_demo()
        with TestClient(app) as cl:
            r=cl.get("/health"); print(f"    GET /health  -> {r.status_code} {r.json()}")
            t0=time.perf_counter()
            r=cl.get("/send/50")
            print(f"    GET /send/50 -> {r.status_code} {r.json()}  耗时 {time.perf_counter()-t0:.3f}s")
        print(f"    ✓ lifespan 内 start/stop，请求内 await send —— 正确挂载方式")
    except Exception as e:
        print(f"    ✗ {type(e).__name__}: {str(e)[:80]}")

asyncio.run(main())
PYEOF
docker cp /tmp/l11_api.py l11-build:/api.py >/dev/null
docker exec l11-build /app/.venv/bin/python /api.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -35
