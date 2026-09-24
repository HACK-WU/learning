#!/bin/bash
# 阶段 3 探路 2：集群健康 + topic 能力 + 两库 API 差异（只读）
set -u
B=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench

echo "=== 1. 集群 topic 列表 ==="
docker exec l15-kafka-1 /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --list 2>&1 | head -20

echo ""
echo "=== 2. 集群 broker API 版本（压缩相关） ==="
docker exec l15-kafka-1 /opt/kafka/bin/kafka-broker-api-versions.sh \
  --bootstrap-server localhost:9092 2>/dev/null | head -3

echo ""
echo "=== 3. broker 端压缩配置默认值 ==="
docker exec l15-kafka-1 /opt/kafka/bin/kafka-configs.sh \
  --bootstrap-server localhost:9092 --entity-type brokers \
  --entity-default --describe 2>/dev/null | grep -i compress || echo "  （无全局压缩覆盖 → 用默认 producer 侧决定）"

cat > /tmp/probe2.py <<'PYEOF'
import inspect
import kafka

print("=== 4. kafka 模块真实来源与版本 ===")
print(f"  kafka.__file__ = {kafka.__file__}")
print(f"  kafka.__version__ = {getattr(kafka,'__version__','无')}")

from kafka import KafkaProducer
print("\n=== 5. 压缩：本库支持哪些 codec ===")
try:
    from kafka.record import util as _u
except Exception:
    pass
for mod in ("kafka.codec", "kafka.record.legacy_records", "kafka.record.memory_records"):
    try:
        m = __import__(mod, fromlist=["x"])
        names = [n for n in dir(m) if "compress" in n.lower() or "codec" in n.lower()]
        if names:
            print(f"  {mod}: {names}")
    except Exception as e:
        print(f"  {mod}: {type(e).__name__}")

print("\n=== 6. 逐个数：能不能真的构造各 codec ===")
for c in (None, "gzip", "snappy", "lz4", "zstd"):
    try:
        p = KafkaProducer(bootstrap_servers="kafka-1:9092",
                          compression_type=c, max_block_ms=3000)
        print(f"  compression_type={str(c):<8} → 构造 OK")
        p.close()
    except Exception as e:
        print(f"  compression_type={str(c):<8} → {type(e).__name__}: {str(e)[:70]}")
PYEOF

echo ""
echo "=== 7. 在基准镜像里跑 codec 探测（联网到 kafka-net） ==="
docker run --rm --network stage6-observability_kafka-net \
  -v /tmp/probe2.py:/probe2.py kafka-pybench:3.12 \
  /app/.venv/bin/python /probe2.py 2>&1 \
  | grep -v -e 'rdkafka#' -e 'Unclosed' | head -30
