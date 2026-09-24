"""课 2：确认 aiokafka acks 哨兵 _missing 的实际生效值（在 async 上下文构造）。

源码逻辑（producer.py:227 附近）：
    if acks is _missing:
        acks = -1 if enable_idempotence else 1
即在 aiokafka 里 acks 跟随 enable_idempotence，而 aiokafka 默认 idempotence=False
→ 实际 acks=1；kafka-python 默认 idempotence=True → acks=-1。
"""
import asyncio
import inspect

from aiokafka import AIOKafkaProducer
from aiokafka.producer.producer import _missing

print("=== 哨兵 _missing 确认 ===")
sig = inspect.signature(AIOKafkaProducer.__init__)
print(f"  acks 默认值 is _missing: {sig.parameters['acks'].default is _missing}")

print("\n=== 源码里的分支逻辑 ===")
src = inspect.getsource(AIOKafkaProducer.__init__)
lines = src.splitlines()
for i, line in enumerate(lines):
    if "acks is _missing" in line or "enable_idempotence" in line:
        print(f"    {line.strip()}")

print("\n=== 实际生效值（async 上下文构造）===")


async def main():
    cases = [
        ("默认", {}),
        ("enable_idempotence=True", {"enable_idempotence": True}),
        ("enable_idempotence=False", {"enable_idempotence": False}),
        ("acks=-1 显式", {"acks": -1}),
        ("acks=1 显式", {"acks": 1}),
    ]
    for label, kw in cases:
        try:
            p = AIOKafkaProducer(bootstrap_servers="kafka-1:9092", **kw)
            print(f"  {label:<28} → _acks={p._acks!r}  idempotence={getattr(p,'_enable_idempotence','?')!r}")
        except Exception as e:
            print(f"  {label:<28} → 报错 {type(e).__name__}: {str(e)[:70]}")


asyncio.run(main())

print("\n=== kafka-python 对照 ===")
from kafka import KafkaProducer
print(f"  DEFAULT_CONFIG acks           = {KafkaProducer.DEFAULT_CONFIG['acks']!r}")
print(f"  DEFAULT_CONFIG enable_idempotence = {KafkaProducer.DEFAULT_CONFIG.get('enable_idempotence', '（无此项）')!r}")
