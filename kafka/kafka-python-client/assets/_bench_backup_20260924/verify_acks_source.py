"""课 2：直接打印 aiokafka 源码中 acks 的分支逻辑（不猜属性名）。

前几版都在找实例属性（_acks / acks / vars() 都没有）。
结论：aiokafka 把 acks 传给了内部 client，不在实例顶层。
所以改为「读源码确认分支」——这是确定性的。
"""
import inspect

from aiokafka import AIOKafkaProducer
from aiokafka.producer.producer import _missing

print("=== 确认默认参数是哨兵 _missing ===")
sig = inspect.signature(AIOKafkaProducer.__init__)
print(f"  acks default is _missing: {sig.parameters['acks'].default is _missing}")
print(f"  enable_idempotence default: {sig.parameters['enable_idempotence'].default!r}")

print("\n=== 源码：acks 的完整分支逻辑 ===")
src = inspect.getsource(AIOKafkaProducer.__init__)
lines = src.splitlines()
start = None
for i, line in enumerate(lines):
    if "acks not in (0, 1, -1" in line:
        start = max(0, i - 3)
        break
if start is not None:
    for line in lines[start:start + 24]:
        print(f"  {line}")
else:
    print("  （未定位到分支，打印全部含 acks 的行）")
    for line in lines:
        if "acks" in line:
            print(f"  {line}")

print("\n=== 结论（由源码直接推出）===")
print("  acks 默认 = _missing（哨兵，不是具体值）")
print("  分支：if acks is _missing:")
print("          acks = -1 if enable_idempotence else 1")
print("  而 enable_idempotence 默认 False")
print("  → aiokafka 默认 acks = 1（仅 leader 确认）")

print("\n=== 对照 kafka-python ===")
from kafka import KafkaProducer
print(f"  acks 默认               = {KafkaProducer.DEFAULT_CONFIG['acks']!r}  (all)")

idem = KafkaProducer.DEFAULT_CONFIG.get("enable_idempotence", "（无此项）")
print(f"  enable_idempotence 默认 = {idem!r}")
print("  → kafka-python 默认 acks = -1（全 ISR 确认）+ 幂等开启")

print("\n=== ⚠️ 换库影响 ===")
print("  同样的 producer 代码，从 kafka-python 换到 aiokafka：")
print("    可靠性语义从「全副本确认 + 幂等」降级为「仅 leader 确认，无幂等」")
print("  且不会报错 —— 静默降级，这是最危险的一类差异")
