"""课 4：背压真相 —— buffer_memory=None 意味着什么？

猜想：kafka-python 没有真正的内存池（Java 客户端有 BufferPool）。
验证：
  1. buffer_memory=None → 搜源码里它被用在哪
  2. 没有 BufferPool 类 → 说明不限制内存
  3. 实测：疯狂 send 会不会 OOM / 阻塞？
"""
import inspect

from kafka.producer import record_accumulator as ra
from kafka.producer.record_accumulator import RecordAccumulator

print("=== 1. 源码里 buffer_memory 出现在哪 ===")
src = inspect.getsource(ra)
hit = False
for i, line in enumerate(src.split("\n"), 1):
    if "buffer_memory" in line:
        print(f"  L{i}: {line.rstrip()}")
        hit = True
if not hit:
    print("  （record_accumulator.py 里根本没出现 buffer_memory）")

print("\n=== 2. 整个 kafka 包搜 BufferPool / buffer_memory ===")
import os
import kafka

root = os.path.dirname(kafka.__file__)
found = []
for dp, dn, fn in os.walk(root):
    if "__pycache__" in dp or "vendor" in dp:
        continue
    for f in fn:
        if not f.endswith(".py"):
            continue
        p = os.path.join(dp, f)
        try:
            with open(p, encoding="utf-8", errors="ignore") as fh:
                for i, line in enumerate(fh, 1):
                    if "BufferPool" in line or "buffer_memory" in line:
                        found.append((os.path.relpath(p, root), i, line.rstrip()[:110]))
        except OSError:
            pass
if found:
    for f, i, l in found[:25]:
        print(f"  {f}:{i}: {l}")
    print(f"  ... 共 {len(found)} 处")
else:
    print("  → 整个 kafka 包没有 BufferPool，也没有使用 buffer_memory")

print("\n=== 3. DEFAULT_CONFIG 里 buffer_memory 的注释 ===")
try:
    from kafka.producer.kafka import KafkaProducer
    src2 = inspect.getsource(KafkaProducer)
    for i, line in enumerate(src2.split("\n"), 1):
        if "buffer_memory" in line:
            print(f"  L{i}: {line.rstrip()[:150]}")
except Exception as e:
    print(f"  {e}")

print("\n=== 4. max_block_ms 用在哪（背压另一条路）===")
from kafka.producer.kafka import KafkaProducer
src3 = inspect.getsource(KafkaProducer)
for i, line in enumerate(src3.split("\n"), 1):
    if "max_block_ms" in line:
        print(f"  L{i}: {line.rstrip()[:140]}")

print("\n=== 5. _ensure_valid_record_size（单条上限）===")
try:
    print(inspect.getsource(KafkaProducer._ensure_valid_record_size))
except Exception as e:
    print(f"  {type(e).__name__}: {e}")

print("\n=== 6. retries=inf 的真相 ===")
print(f"  DEFAULT_CONFIG['retries'] = {KafkaProducer.DEFAULT_CONFIG.get('retries')}")
import math
v = KafkaProducer.DEFAULT_CONFIG.get("retries")
print(f"  是 inf? {v == float('inf')}")
src4 = inspect.getsource(ra)
for i, line in enumerate(src4.split("\n"), 1):
    if "retries" in line and "retry" in line.lower():
        print(f"  accum L{i}: {line.rstrip()[:130]}")
