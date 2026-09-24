#!/bin/bash
# 课 11 探路：async 三方可用性 + 那个被推翻的前提
set -u
cat > /tmp/l11_probe.py <<'PYEOF'
import sys, importlib, inspect

print("=" * 74)
print("课 11 探路：async 三方库可用性")
print("=" * 74)
print(f"Python: {sys.version.split()[0]}\n")

# ---------- 1. aiokafka ----------
print("────── 1. aiokafka ──────")
try:
    import aiokafka
    print(f"  版本          : {aiokafka.__version__}")
    print(f"  路径          : {aiokafka.__file__}")
    from aiokafka import AIOKafkaProducer, AIOKafkaConsumer
    print(f"  AIOKafkaProducer : ✓")
    print(f"  AIOKafkaConsumer : ✓")
except ImportError as e:
    print(f"  ✗ 未安装: {e}")

# ---------- 2. confluent AIOConsumer / AIOProducer ----------
print(f"\n────── 2. confluent-kafka AIO* （课 11 核心前提）──────")
import confluent_kafka as ck
print(f"  版本          : {ck.version()}  / librdkafka {ck.libversion()}")
for name in ["AIOProducer", "AIOConsumer", "AIOAdminClient"]:
    has = hasattr(ck, name)
    print(f"  {name:<16}: {'✓ 存在' if has else '✗ 不存在'}")

print(f"\n  ⚠ 阶段4 overview 记载：confluent 2.13.0 起 AIO* 正式 GA")
print(f"     本机版本 {ck.version()} -> ", end="")
v = tuple(int(x) for x in ck.version().split(".")[:3] if x.isdigit())
if v >= (2,13,0):
    print(f">= 2.13.0，前提成立，需实测验证")
else:
    print(f"< 2.13.0，前提【不成立】，overview 记载有误")

# ---------- 3. AIOConsumer 真实签名 ----------
if hasattr(ck, "AIOConsumer"):
    print(f"\n  AIOConsumer 签名:")
    try:
        print(f"    {inspect.signature(ck.AIOConsumer.__init__)}")
    except Exception as e:
        print(f"    (无法读取: {e})")
    print(f"  方法（与同步 Consumer 对比）:")
    m_sync = set(x for x in dir(ck.Consumer) if not x.startswith("_"))
    m_aio  = set(x for x in dir(ck.AIOConsumer) if not x.startswith("_"))
    only_aio = sorted(m_aio - m_sync)
    print(f"    AIO* 独有: {only_aio}")
    # 关键：poll 是不是 coroutine
    for mn in ["poll", "commit", "consume"]:
        if hasattr(ck.AIOConsumer, mn):
            f = getattr(ck.AIOConsumer, mn)
            print(f"    {mn:<10} 是 coroutine? {inspect.iscoroutinefunction(f)}")

# ---------- 4. 依赖检查 ----------
print(f"\n────── 3. 相关依赖 ──────")
for m in ["asyncio", "fastapi", "uvicorn", "httpx", "kafka"]:
    try:
        mod = importlib.import_module(m)
        print(f"  {m:<10}: ✓ {getattr(mod,'__version__','?')}")
    except ImportError:
        print(f"  {m:<10}: ✗ 未安装")

print(f"\n{'='*74}")
PYEOF
docker run --rm --network bench_kafka-net -v /tmp/l11_probe.py:/p.py \
  kafka-pybench:3.12 /app/.venv/bin/python /p.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -45
