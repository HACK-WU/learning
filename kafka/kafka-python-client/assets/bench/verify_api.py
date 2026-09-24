"""核验（第二轮）：上一轮对构造参数的判定是误报。

原因：KafkaProducer/KafkaConsumer 用 **configs 收参（**kwargs 风格），
      inspect.signature(__init__) 看不到真实配置项。

正确做法：直接读类的 DEFAULT_CONFIG / 文档字符串枚举出的合法键。
"""

import kafka
from kafka import KafkaConsumer, KafkaProducer

print("kafka-python version:", kafka.__version__)
print()

producer_keys = set(KafkaProducer.DEFAULT_CONFIG)
consumer_keys = set(KafkaConsumer.DEFAULT_CONFIG)

print("=== KafkaProducer 关键配置项是否存在 ===")
for k in ["acks", "retries", "enable_idempotence", "linger_ms",
          "buffer_memory", "max_block_ms", "compression_type",
          "bootstrap_servers", "value_serializer", "key_serializer"]:
    print(f"  {k}: {'✅ 存在 默认=' + repr(KafkaProducer.DEFAULT_CONFIG[k]) if k in producer_keys else '❌ 不存在'}")
print()

print("=== KafkaConsumer 关键配置项是否存在 ===")
for k in ["enable_auto_commit", "auto_offset_reset", "max_poll_records",
          "group_id", "bootstrap_servers", "value_deserializer",
          "consumer_timeout_ms", "max_partition_fetch_bytes"]:
    print(f"  {k}: {'✅ 存在 默认=' + repr(KafkaConsumer.DEFAULT_CONFIG[k]) if k in consumer_keys else '❌ 不存在'}")
print()

print("=== 提交方法确认（实战 09 用的是 commitSync） ===")
for m in ["commit", "commit_async", "commitSync"]:
    print(f"  KafkaConsumer.{m}: {'✅ 存在' if hasattr(KafkaConsumer, m) else '❌ 不存在'}")
print()

print("=== commit 签名 ===")
import inspect
print("commit:", inspect.signature(KafkaConsumer.commit))
