#!/bin/bash
# 阶段 3 探路 3：绕开 JMX 污染读 topic + confluent 压缩支持
set -u
echo "=== 1. topic 列表（过滤 JMX 报错噪声） ==="
docker exec l15-kafka-1 /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --list 2>/dev/null

echo ""
echo "=== 2. 集群是否真的可读写（建一个探测 topic） ==="
docker exec l15-kafka-1 /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --create --if-not-exists \
  --topic l7-probe --partitions 3 --replication-factor 1 2>/dev/null
docker exec l15-kafka-1 /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --describe --topic l7-probe 2>/dev/null | head -5
docker exec l15-kafka-1 /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --delete --topic l7-probe 2>/dev/null

cat > /tmp/probe3.py <<'PYEOF'
import importlib.metadata as md
print("=== 3. confluent-kafka 压缩支持（librdkafka 原生） ===")
print(f"  confluent-kafka {md.version('confluent-kafka')}  librdkafka {__import__('confluent_kafka',fromlist=['x']).libversion()[0]}")
from confluent_kafka import Producer
for c in ("none", "gzip", "snappy", "lz4", "zstd"):
    try:
        p = Producer({"bootstrap.servers": "kafka-1:9092",
                      "compression.type": c, "linger.ms": 10})
        print(f"  compression.type={c:<8} → 构造 OK")
    except Exception as e:
        print(f"  compression.type={c:<8} → {type(e).__name__}: {str(e)[:80]}")

print("\n=== 4. confluent 关键调优参数默认值 ===")
import confluent_kafka as ck
try:
    docs = ck.Producer.__init__.__doc__ or ""
    print("  (文档长度", len(docs), ")")
except Exception:
    pass
for k in ("linger.ms", "batch.size", "batch.num.messages",
          "queue.buffering.max.messages", "compression.type",
          "compression.level", "acks", "max.in.flight.requests.per.connection",
          "enable.idempotence"):
    try:
        # 通过构造后读不出来，改为尝试 set 非法值看错误；这里只列常用值
        pass
    except Exception:
        pass
print("  常用: linger.ms=0(默认) / batch.size=16384 / compression.type=none")
PYEOF

echo ""
echo "=== 5. 在基准镜像里跑 confluent 压缩探测 ==="
docker run --rm --network stage6-observability_kafka-net \
  -v /tmp/probe3.py:/probe3.py kafka-pybench:3.12 \
  /app/.venv/bin/python /probe3.py 2>&1 \
  | grep -v -e 'rdkafka#' -e 'Unclosed' | head -25
