#!/bin/bash
# 阶段 3 探路：基准镜像里到底装了什么（只读，不改环境）
set -u
B=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
IMG=kafka-pybench:3.12

cat > /tmp/probe_env.py <<'PYEOF'
import importlib.metadata as md

print("=== 1. 镜像内已装库 ===")
for p in ("kafka-python", "kafka-python-ng", "confluent-kafka"):
    try:
        print(f"  {p:<18} {md.version(p)}")
    except Exception:
        print(f"  {p:<18} 【未安装】")

print("\n=== 2. librdkafka / confluent 能力 ===")
try:
    from confluent_kafka import libversion
    v = libversion()
    print(f"  librdkafka        : {v[0]}")
    print(f"  confluent-kafka   : {md.version('confluent-kafka')}")
except Exception as e:
    print(f"  {type(e).__name__}: {e}")

print("\n=== 3. 两库压缩参数名对照（不猜，直接读） ===")
try:
    import kafka as kp
    print(f"  kafka-python 版本 : {kp.__version__ if hasattr(kp,'__version__') else '?'}")
    from kafka import KafkaProducer
    print(f"  compression_type 默认 = {KafkaProducer.DEFAULT_CONFIG.get('compression_type')!r}")
    print(f"  linger_ms        默认 = {KafkaProducer.DEFAULT_CONFIG.get('linger_ms')!r}")
    print(f"  batch_size       默认 = {KafkaProducer.DEFAULT_CONFIG.get('batch_size')!r}")
except Exception as e:
    print(f"  kafka-python 未装: {type(e).__name__}")
try:
    import kafka as kpng
    print(f"\n  kafka-python-ng   : {md.version('kafka-python-ng')}")
    from kafka import KafkaProducer as P2
    print(f"  compression_type 默认 = {P2.DEFAULT_CONFIG.get('compression_type')!r}")
    print(f"  linger_ms        默认 = {P2.DEFAULT_CONFIG.get('linger_ms')!r}")
    print(f"  batch_size       默认 = {P2.DEFAULT_CONFIG.get('batch_size')!r}")
except Exception as e:
    print(f"  {type(e).__name__}: {e}")
PYEOF

docker run --rm -v /tmp/probe_env.py:/probe.py "$IMG" /app/.venv/bin/python /probe.py 2>&1 \
  | grep -v -e 'rdkafka#' -e 'Unclosed'

echo ""
echo "=== 4. 集群与 topic 现状（只读） ==="
docker exec l15-kafka-1 /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --list 2>/dev/null | head -20
