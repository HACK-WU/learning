"""课 2：确认 aiokafka 的 acks 哨兵对象到底是什么，以及它的实际默认行为。

实测发现：aiokafka 的 acks 默认是 <object object at ...>（哨兵），
kafka-python 是 -1。需要确认哨兵代表的真实值。
"""
import inspect

import aiokafka
from aiokafka import AIOKafkaProducer
import aiokafka.producer.producer as pp

print("=== aiokafka acks 哨兵对象 ===")
sig = inspect.signature(AIOKafkaProducer.__init__)
d = sig.parameters["acks"].default
print(f"  默认值对象: {d!r}")
print(f"  type: {type(d).__name__}")

# 找哨兵定义：在模块里找与 d 是同一对象的名字
print(f"\n  在 aiokafka.producer.producer 里找与默认值同对象的名字:")
hit = None
for n in dir(pp):
    obj = getattr(pp, n, None)
    if obj is d:
        hit = n
        print(f"    {n} = {obj!r}   ← 就是它")
        break
if not hit:
    for n in dir(pp):
        if "UNKNOWN" in n.upper() or "SENTINEL" in n.upper():
            print(f"    {n} = {getattr(pp, n)!r}")

print("\n=== 哨兵的实际含义：看 __init__ 里怎么用 ===")
src = inspect.getsource(AIOKafkaProducer.__init__)
for line in src.splitlines():
    if "acks" in line:
        print(f"    {line.strip()}")

print("\n=== 实际生效值：构造后读实例的 _acks ===")
p = AIOKafkaProducer(bootstrap_servers="kafka-1:9092")
for attr in ["_acks", "acks"]:
    v = getattr(p, attr, "（无此属性）")
    print(f"  {attr} = {v!r}")

print("\n=== 对比：显式指定 acks 时 ===")
for v in [-1, 0, 1, "all"]:
    try:
        p2 = AIOKafkaProducer(bootstrap_servers="kafka-1:9092", acks=v)
        print(f"  acks={v!r:<6} → 实例 _acks = {getattr(p2, '_acks', '?')!r}")
    except Exception as e:
        print(f"  acks={v!r:<6} → 报错 {type(e).__name__}: {str(e)[:60]}")

print("\n=== kafka-python 对照 ===")
from kafka import KafkaProducer
print(f"  KafkaProducer.DEFAULT_CONFIG['acks'] = {KafkaProducer.DEFAULT_CONFIG['acks']!r}")
p3 = KafkaProducer(bootstrap_servers="kafka-1:9092")
print(f"  实例 config['acks'] = {p3.config['acks']!r}")
