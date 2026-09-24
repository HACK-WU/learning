#!/bin/bash
# 课 8 核心实测②：僵尸实例 fencing
# 同一 transactional_id 启两个 producer，老的必须被 fence 掉（epoch 递增）
set -u
SRC=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
NET=stage6-observability_kafka-net

cat > /tmp/fz.py <<'PYEOF'
import sys, time
from common import BOOTSTRAP
LIB = sys.argv[1]
T = "l8-fence-topic"
TXID = f"l8-fence-tx-{int(time.time())}"

def mk_admin():
    from kafka.admin import KafkaAdminClient, NewTopic
    a = KafkaAdminClient(bootstrap_servers=BOOTSTRAP, request_timeout_ms=15000)
    try: a.delete_topics([T], timeout_ms=15000); time.sleep(1)
    except Exception: pass
    try: a.create_topics([NewTopic(T, num_partitions=3, replication_factor=1)], timeout_ms=15000)
    except Exception: pass
    a.close(); time.sleep(2)

mk_admin()

if LIB == "kp":
    from kafka import KafkaProducer
    from kafka.errors import ProducerFencedError
    def mk():
        return KafkaProducer(bootstrap_servers=BOOTSTRAP, transactional_id=TXID,
                             enable_idempotence=True, acks="all", max_block_ms=30000)
    p1 = mk(); p1.init_transactions()
    print("  producer-1 init OK")
    p1.begin_transaction(); p1.send(T, b"from-p1"); p1.flush()
    print("  producer-1 已发送（未提交）")

    p2 = mk(); p2.init_transactions()
    print("  producer-2 init OK  <- 同 transactional_id，触发 epoch bump")
    p2.begin_transaction(); p2.send(T, value=b"from-p2")
    p2.commit_transaction()
    print("  producer-2 提交成功")

    time.sleep(1)
    try:
        p1.commit_transaction()
        print("  ✗ producer-1 竟然提交成功了（未 fence！）")
    except ProducerFencedError as e:
        print(f"  ✓ producer-1 被 fence: ProducerFencedError")
    except Exception as e:
        print(f"  ? producer-1 抛 {type(e).__name__}: {str(e)[:110]}")

    time.sleep(1)
    from kafka import KafkaConsumer
    c = KafkaConsumer(T, bootstrap_servers=BOOTSTRAP, group_id=None,
                      auto_offset_reset="earliest", enable_auto_commit=False,
                      isolation_level="read_committed", consumer_timeout_ms=6000)
    got = [m.value.decode() for m in c]; c.close()
    print(f"  read_committed 可见: {got}  <- 应只有 from-p2")
else:
    from confluent_kafka import Producer as CP
    from confluent_kafka.error import KafkaException
    def mk():
        return CP({"bootstrap.servers": BOOTSTRAP, "transactional.id": TXID,
                   "enable.idempotence": True, "acks": "all",
                   "transaction.timeout.ms": 60000})
    p1 = mk(); p1.init_transactions()
    print("  producer-1 init OK")
    p1.begin_transaction(); p1.produce(T, b"from-p1"); p1.poll(0)
    print("  producer-1 已发送（未提交）")

    p2 = mk(); p2.init_transactions()
    print("  producer-2 init OK  <- 同 transactional_id，触发 epoch bump")
    p2.begin_transaction(); p2.produce(T, value=b"from-p2")
    p2.commit_transaction()
    print("  producer-2 提交成功")

    time.sleep(1)
    try:
        p1.commit_transaction()
        print("  ✗ producer-1 竟然提交成功了（未 fence！）")
    except Exception as e:
        print(f"  ? producer-1 抛 {type(e).__name__}: {str(e)[:130]}")

    time.sleep(1)
    from kafka import KafkaConsumer
    c = KafkaConsumer(T, bootstrap_servers=BOOTSTRAP, group_id=None,
                      auto_offset_reset="earliest", enable_auto_commit=False,
                      isolation_level="read_committed", consumer_timeout_ms=6000)
    got = [m.value.decode() for m in c]; c.close()
    print(f"  read_committed 可见: {got}  <- 应只有 from-p2")
PYEOF

for L in kp cf; do
  echo "===== 僵尸实例 fencing [$L] ====="
  docker run --rm --network $NET -v "$SRC":/app/scripts -v /tmp/fz.py:/f.py \
    -e PYTHONPATH=/app/scripts kafka-pybench:3.12 \
    /app/.venv/bin/python /f.py $L 2>&1 \
    | grep -v -e 'rdkafka#' -e 'Unclosed' | head -14
done
