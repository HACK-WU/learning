#!/bin/bash
# 课 11 二次探路：确认三方 async 方案真实可用（不是"装上了"就算数）
set -u
cat > /tmp/l11_p2.py <<'PYEOF'
import sys, inspect, time
print("=" * 74); print("课 11 三方 async 方案可用性核验"); print("=" * 74)
print(f"Python {sys.version.split()[0]}\n")

# ---- A: aiokafka ----
print("────── A. aiokafka ──────")
try:
    import aiokafka
    from aiokafka import AIOKafkaProducer, AIOKafkaConsumer
    print(f"  版本 {aiokafka.__version__}  ✓ AIOKafkaProducer/Consumer")
except ImportError as e:
    print(f"  ✗ {e}"); AIOKafkaProducer = None

# ---- B: confluent AIOConsumer ----
print(f"\n────── B. confluent_kafka.aio.AIOConsumer ──────")
import confluent_kafka as ck
from confluent_kafka.aio import AIOConsumer, AIOProducer
print(f"  版本 {ck.version()}  ✓ AIOConsumer/AIOProducer（注意：子模块，顶层查不到）")
for mn in ["poll","commit","consume","subscribe","get_watermark_offsets"]:
    if hasattr(AIOConsumer, mn):
        f = getattr(AIOConsumer, mn)
        print(f"    {mn:<22} coroutine={inspect.iscoroutinefunction(f)}")
print(f"  AIOProducer.__init__: {inspect.signature(AIOProducer.__init__)}")

# ---- C: fastapi / uvicorn ----
print(f"\n────── C. FastAPI 场景层 ──────")
import fastapi, uvicorn
print(f"  fastapi {fastapi.__version__}  uvicorn {uvicorn.__version__}  ✓")

# ---- 关键：AIOConsumer 是不是"真 async"还是线程池伪装 ----
print(f"\n────── D. AIOConsumer 是『真 async』还是『线程池伪装』？──────")
src = inspect.getsource(AIOConsumer.consume) if hasattr(AIOConsumer,'consume') else ""
import re
print(f"  consume() 源码（前 15 行）:")
for ln in src.split("\n")[:15]:
    if ln.strip(): print(f"    {ln}")
print(f"\n  判据：若内部出现 run_in_executor -> 线程池伪装（受 GIL 约束）")
print(f"        若是 await + 事件循环      -> 真 async IO")
PYEOF
docker cp /tmp/l11_p2.py l11-build:/p2.py >/dev/null
docker exec l11-build /app/.venv/bin/python /p2.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -45
