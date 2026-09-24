#!/bin/bash
# 课 8 探路：三库事务 API 真实存在性核验（不猜，逐个 hasattr）
set -u
cat > /tmp/t.py <<'PYEOF'
import importlib.metadata as md

def show(lib):
    print(f"\n{'='*60}\n{lib}  {md.version(lib)}\n{'='*60}")

# ---------- confluent-kafka ----------
try:
    show("confluent-kafka")
    from confluent_kafka import Producer, Consumer
    for m in ("init_transactions","begin_transaction","commit_transaction",
              "abort_transaction","send_offsets_to_transaction"):
        print(f"  Producer.{m:<30} = {hasattr(Producer, m)}")
    for m in ("subscribe","consume","commit","close"):
        print(f"  Consumer.{m:<30} = {hasattr(Consumer, m)}")
    import inspect
    print("\n  send_offsets_to_transaction 签名:")
    print(f"    {inspect.signature(Producer.send_offsets_to_transaction)}")
    print("  init_transactions 签名:")
    print(f"    {inspect.signature(Producer.init_transactions)}")
except Exception as e:
    print(f"  ERR {e}")

# ---------- kafka-python ----------
try:
    show("kafka-python")
    import kafka
    P, C = kafka.KafkaProducer, kafka.KafkaConsumer
    for m in ("init_transactions","begin_transaction","commit_transaction",
              "abort_transaction","send_offsets_to_transaction"):
        print(f"  KafkaProducer.{m:<26} = {hasattr(P, m)}")
    for m in ("init_transactions","begin_transaction","commit_transaction",
              "abort_transaction","send_offsets_to_transaction"):
        print(f"  KafkaConsumer.{m:<26} = {hasattr(C, m)}")
    print("\n  KafkaProducer.DEFAULT_CONFIG 中事务相关键:")
    for k in sorted(P.DEFAULT_CONFIG):
        if any(w in k.lower() for w in ("transaction", "idempot", "isolation")):
            print(f"    {k:<40} = {P.DEFAULT_CONFIG[k]!r}")
    print("\n  KafkaConsumer.DEFAULT_CONFIG 中 isolation/事务相关键:")
    for k in sorted(C.DEFAULT_CONFIG):
        if any(w in k.lower() for w in ("isolation", "transaction")):
            print(f"    {k:<40} = {C.DEFAULT_CONFIG[k]!r}")
except Exception as e:
    print(f"  ERR {e}")
PYEOF
docker run --rm -v /tmp/t.py:/t.py kafka-pybench:3.12 \
  /app/.venv/bin/python /t.py 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed'

echo ""
echo "########## kafka-python-ng 单独核验 ##########"
docker run --rm -v /mnt/d/projects/learning/kafka/kafka-python-client/assets/bench/probe_ng_txn.py:/n.py \
  python:3.12-slim sh -c 'pip install -q kafka-python-ng==2.2.3 >/dev/null 2>&1; python /n.py' 2>&1 | tail -20
