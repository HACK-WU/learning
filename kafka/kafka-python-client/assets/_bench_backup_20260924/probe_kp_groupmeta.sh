#!/bin/bash
set -u
cat > /tmp/gm.py <<'PYEOF'
import inspect
from kafka import KafkaConsumer
from kafka.coordinator.consumer import ConsumerCoordinator
from kafka.consumer.group import ConsumerGroupMetadata
print("=== ConsumerGroupMetadata 定义 ===")
print(f"  类: {ConsumerGroupMetadata}")
try:
    print(f"  字段: {ConsumerGroupMetadata._fields}")
except Exception as e:
    print(f"  字段: <{e}>")
print(f"  构造: {inspect.signature(ConsumerGroupMetadata)}")

print("\n=== KafkaConsumer.group_metadata 属性 ===")
f = getattr(KafkaConsumer, "group_metadata", None)
print(f"  类型: {type(f)}")
if isinstance(f, property):
    print(f"  getter 签名: {inspect.signature(f.fget)}")
try:
    src = inspect.getsource(f.fget)
    print("\n--- group_metadata 源码 ---")
    print(src)
except Exception as e:
    print(f"  取源码失败: {e}")

print("\n=== send_offsets_to_transaction 源码（含类型要求）===")
from kafka import KafkaProducer
src2 = inspect.getsource(KafkaProducer.send_offsets_to_transaction)
print(src2[:2200])
PYEOF
docker run --rm -v /tmp/gm.py:/g.py kafka-pybench:3.12 \
  /app/.venv/bin/python /g.py 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed' | head -60
