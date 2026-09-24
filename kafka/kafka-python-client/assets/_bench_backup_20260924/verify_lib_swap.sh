#!/bin/bash
# 换库后回归：确认 3.0.11 装对 + 压缩 codec 真的可用（不猜，逐个构造）
set -u
cat > /tmp/v.py <<'PYEOF'
import importlib.metadata as md
import kafka
print("=== 1. 版本确认 ===")
print(f"  kafka-python      : {md.version('kafka-python')}")
print(f"  kafka.__version__ : {getattr(kafka,'__version__','?')}")
print(f"  confluent-kafka   : {md.version('confluent-kafka')}")
import confluent_kafka as ck
print(f"  librdkafka        : {ck.libversion()[0]}")

print("\n=== 2. kafka-python 3.0.11 默认配置（课 6 讲过的 KIP-679） ===")
from kafka import KafkaProducer
D = KafkaProducer.DEFAULT_CONFIG
for k in ("enable_idempotence", "acks", "retries", "compression_type",
          "linger_ms", "batch_size", "max_in_flight_requests_per_connection"):
    print(f"  {k:<40} = {D.get(k)!r}")

print("\n=== 3. kafka-python 压缩 codec 逐个构造 ===")
from kafka import KafkaProducer as KP
for c in (None, "gzip", "snappy", "lz4", "zstd"):
    try:
        p = KP(bootstrap_servers="kafka-1:9092", compression_type=c,
               max_block_ms=5000, request_timeout_ms=8000)
        print(f"  compression_type={str(c):<8} → OK")
        p.close()
    except Exception as e:
        print(f"  compression_type={str(c):<8} → {type(e).__name__}: {str(e)[:60]}")

print("\n=== 4. confluent 压缩 codec 逐个构造 ===")
from confluent_kafka import Producer as CP
for c in ("none", "gzip", "snappy", "lz4", "zstd"):
    try:
        p = CP({"bootstrap.servers": "kafka-1:9092", "compression.type": c})
        print(f"  compression.type={c:<8} → OK")
    except Exception as e:
        print(f"  compression.type={c:<8} → {type(e).__name__}: {str(e)[:60]}")
PYEOF
docker run --rm --network stage6-observability_kafka-net \
  -v /tmp/v.py:/v.py kafka-pybench:3.12 \
  /app/.venv/bin/python /v.py 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed' | head -40
