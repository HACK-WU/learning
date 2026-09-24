"""课 5：消费者源码总览 —— 先摸清结构，再深挖。

课 4 教训：不要猜方法名（_allocate 不存在）。
这版先把 consumer 包的文件、类、方法全列出来。
"""
import inspect
import os

import kafka

root = os.path.dirname(kafka.__file__)
print(f"kafka-python 3.0.11  包路径: {root}")

print("\n=== 1. consumer 目录 ===")
cd = os.path.join(root, "consumer")
for f in sorted(os.listdir(cd)):
    if f.endswith(".py"):
        p = os.path.join(cd, f)
        print(f"  {f:<26} {os.path.getsize(p):>7} bytes")

print("\n=== 2. KafkaConsumer 的类继承链 ===")
from kafka import KafkaConsumer

for i, c in enumerate(KafkaConsumer.__mro__):
    print(f"  {i}. {c.__module__}.{c.__name__}")

print("\n=== 3. KafkaConsumer 自己的方法（非继承）===")
own = [n for n in vars(KafkaConsumer) if not n.startswith("_")]
print(f"  {sorted(own)}")

print("\n=== 4. 含 poll / fetch / commit / position 的 ===")
allm = [n for n in dir(KafkaConsumer) if not n.startswith("__")]
for kw in ("poll", "fetch", "commit", "position", "seek", "assign", "subscribe"):
    hits = [n for n in allm if kw in n.lower()]
    print(f"  {kw:<12} -> {hits}")

print("\n=== 5. Fetcher 类结构 ===")
try:
    from kafka.consumer.fetcher import Fetcher
    print(f"  模块: {Fetcher.__module__}")
    print(f"  方法: {sorted(n for n in dir(Fetcher) if not n.startswith('__'))}")
except Exception as e:
    print(f"  {type(e).__name__}: {e}")

print("\n=== 6. 默认配置（消费者关键项）===")
for k in ("enable_auto_commit", "auto_commit_interval_ms", "group_id",
          "session_timeout_ms", "heartbeat_interval_ms", "max_poll_records",
          "max_poll_interval_ms", "fetch_min_bytes", "fetch_max_wait_ms",
          "fetch_max_bytes", "auto_offset_reset", "isolation_level",
          "rebalance_timeout_ms", "default_offset_commit_callback"):
    try:
        print(f"  {k:<34} = {KafkaConsumer.DEFAULT_CONFIG.get(k)}")
    except Exception as e:
        print(f"  {k:<34} 读取失败: {e}")
