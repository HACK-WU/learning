#!/bin/bash
# 修正版：AIOConsumer 必须在 async 上下文构造（坑 #1）
# 实测：线程池大小 / 真 async 还是伪装 / 三方吞吐对照
set -u
cat > /tmp/l11_dig2.py <<'PYEOF'
import threading, asyncio, time, inspect
from confluent_kafka.aio import AIOConsumer

async def main():
    print("=" * 74); print("AIOConsumer 机制实测（async 上下文内）"); print("=" * 74)
    base = threading.active_count()
    print(f"  构造前线程数: {base}")
    c = AIOConsumer({"bootstrap.servers":"kafka-1:9092,kafka-2:9092,kafka-3:9092",
                     "group.id":"l11-dig","auto.offset.reset":"earliest"})
    time.sleep(0.3)
    after = threading.active_count()
    print(f"  构造后线程数: {after}  (+{after-base})")
    print(f"  线程: {[t.name for t in threading.enumerate()]}")
    print(f"  executor: {c.executor!r}")
    print(f"  max_workers: {getattr(c.executor,'_max_workers','?')}")
    await c.close()
    print(f"\n  ✓ 坑#1：AIOConsumer() 只能在 async 函数内构造")
    print(f"         同步上下文 -> RuntimeError: no running event loop")

asyncio.run(main())
PYEOF
docker cp /tmp/l11_dig2.py l11-build:/d2.py >/dev/null
docker exec l11-build /app/.venv/bin/python /d2.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -25
