"""课 6：幂等与确认语义 —— 源码结构全量列举。

课 4/5 教训：不要猜方法名（_allocate 不存在）。
先把 producer 包结构、幂等相关方法、默认配置全列出来。
"""
import inspect
import os

import kafka

root = os.path.dirname(kafka.__file__)
print(f"kafka-python 3.0.11  包路径: {root}")

print("\n=== 1. producer 目录 ===")
pd = os.path.join(root, "producer")
for f in sorted(os.listdir(pd)):
    if f.endswith(".py"):
        p = os.path.join(pd, f)
        print(f"  {f:<26} {os.path.getsize(p):>7} bytes")

from kafka import KafkaProducer

print("\n=== 2. KafkaProducer 方法（含 acks / idempot / sequence / epoch）===")
allm = [n for n in dir(KafkaProducer) if not n.startswith("__")]
for kw in ("ack", "idempo", "sequence", "epoch", "transact", "flush", "send",
           "partition", "batch", "abort", "commit"):
    hits = [n for n in allm if kw in n.lower()]
    print(f"  {kw:<12} -> {hits}")

print("\n=== 3. 幂等/事务相关默认配置 ===")
keys = ["acks", "enable_idempotence", "retries", "max_in_flight_requests_per_connection",
        "retry_backoff_ms", "request_timeout_ms", "delivery_timeout_ms",
        "transactional_id", "transaction_timeout_ms", "idempotence",
        "max_block_ms", "linger_ms", "batch_size", "compression_type"]
for k in keys:
    try:
        v = KafkaProducer.DEFAULT_CONFIG.get(k, "【不存在此配置】")
        print(f"  {k:<44} = {v}")
    except Exception as e:
        print(f"  {k:<44} 读取失败: {e}")

print("\n=== 4. record_accumulator：幂等相关的序号管理 ===")
try:
    from kafka.producer.record_accumulator import RecordAccumulator
    print(f"  方法: {sorted(n for n in dir(RecordAccumulator) if not n.startswith('_'))}")
except Exception as e:
    print(f"  {type(e).__name__}: {e}")

print("\n=== 5. sender：幂等/epoch 处理 ===")
try:
    from kafka.producer.sender import Sender
    ms = sorted(n for n in dir(Sender) if not n.startswith("_"))
    print(f"  方法({len(ms)}): {ms}")
except Exception as e:
    print(f"  {type(e).__name__}: {e}")

print("\n=== 6. 全包搜索幂等关键字（不猜名字）===")
import subprocess
pkg = root
for kw in ("idempot", "Idempot", "producer_id", "producer_epoch", "base_sequence"):
    try:
        r = subprocess.run(
            ["grep", "-rn", "--include=*.py", kw, pkg],
            capture_output=True, text=True, timeout=30)
        lines = [l for l in r.stdout.split("\n") if l.strip()]
        print(f"\n  【{kw}】命中 {len(lines)} 处:")
        for l in lines[:14]:
            rel = l.replace(pkg + os.sep, "")
            print(f"    {rel[:150]}")
    except Exception as e:
        print(f"  {kw}: {type(e).__name__}: {e}")
