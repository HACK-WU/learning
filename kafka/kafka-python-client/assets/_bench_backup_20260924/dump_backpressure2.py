"""课 4：背压到底在哪（_allocate 不存在，找真实的）。

策略：不猜名字 —— 把 RecordAccumulator / ProducerBatch / Sender 里
跟 buffer_memory / free / 内存分配有关的名字全列出来。
"""
import inspect

from kafka.producer import record_accumulator as ra
from kafka.producer.record_accumulator import RecordAccumulator

print("=== 1. RecordAccumulator 全部方法/属性 ===")
names = [n for n in dir(RecordAccumulator) if not n.startswith("__")]
print(f"  {names}")

print("\n=== 2. 含 buffer / free / memory / alloc 的 ===")
hits = [n for n in names if any(k in n.lower()
        for k in ("buffer", "free", "memory", "alloc", "pool"))]
print(f"  {hits}")

print("\n=== 3. 模块级常量 ===")
mn = [n for n in dir(ra) if n.isupper()]
print(f"  {mn}")
for n in mn:
    print(f"    {n} = {getattr(ra, n)}")

print("\n=== 4. 默认配置里跟缓冲相关的（DEFAULT_CONFIG）===")
from kafka.producer.kafka import KafkaProducer

for k in ("buffer_memory", "max_block_ms", "batch_size", "linger_ms",
          "max_request_size", "compression_type", "acks", "retries",
          "request_timeout_ms", "delivery_timeout_ms"):
    try:
        print(f"  {k:<24} = {KafkaProducer.DEFAULT_CONFIG.get(k)}")
    except Exception as e:
        print(f"  {k:<24} 读取失败: {e}")

print("\n=== 5. 背压现场：在 append 调用链里搜 buffer 相关代码 ===")
src = inspect.getsource(ra)
for i, line in enumerate(src.split("\n"), 1):
    low = line.lower()
    if any(k in low for k in ("buffer_memory", "free()", "_free", "allocate")):
        print(f"  L{i}: {line.rstrip()}")

print("\n=== 6. 看 ProducerBatch 的内存申请 ===")
try:
    from kafka.producer.producer_batch import ProducerBatch
    s = inspect.getsource(ProducerBatch.try_append)
    for i, line in enumerate(s.split("\n"), 1):
        if any(k in line.lower() for k in ("buffer", "free", "alloc", "size")):
            print(f"  L{i}: {line.rstrip()}")
except Exception as e:
    print(f"  {type(e).__name__}: {e}")
