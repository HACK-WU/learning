"""课 4：定位 kafka-python 生产者源码，把关键结构读出来。

本课是「读源码」课，所以第一步是把源码抓到手。
"""
import inspect
import os

import kafka

kp = os.path.dirname(kafka.__file__)
print(f"kafka-python 包路径: {kp}")
print(f"顶层: {sorted(os.listdir(kp))}")

print(f"\n=== producer 目录 ===")
pd = os.path.join(kp, "producer")
for f in sorted(os.listdir(pd)):
    p = os.path.join(pd, f)
    sz = os.path.getsize(p) if os.path.isfile(p) else "-"
    print(f"  {f:<28} {sz}")

# 关键：KafkaProducer.send 的源码
from kafka import KafkaProducer

print("\n" + "=" * 70)
print("KafkaProducer.send 源码")
print("=" * 70)
src = inspect.getsource(KafkaProducer.send)
print(src[:3000])
