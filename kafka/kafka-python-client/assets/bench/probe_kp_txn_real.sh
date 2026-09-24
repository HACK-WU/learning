#!/bin/bash
# 课 8 探路②：kafka-python 3.0.11 的事务是【真能用】还是【只有 API 空壳】？
# hasattr 全 True 不代表能跑——必须真发事务并验消费侧可见性
set -u
SRC=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
NET=stage6-observability_kafka-net

cat > /tmp/tx1.py <<'PYEOF'
import sys, time
from kafka import KafkaProducer, KafkaConsumer
from kafka.admin import KafkaAdminClient, NewTopic
from common import BOOTSTRAP

TAG = sys.argv[1]          # commit | abort
topic = f"l8-tx-{TAG}"
adm = KafkaAdminClient(bootstrap_servers=BOOTSTRAP, request_timeout_ms=15000)
for t in (topic,):
    try: adm.delete_topics([t], timeout_ms=15000); time.sleep(1)
    except Exception: pass
try: adm.create_topics([NewTopic(t, num_partitions=3, replication_factor=1)], timeout_ms=15000)
except Exception: pass
adm.close(); time.sleep(2)

p = KafkaProducer(
    bootstrap_servers=BOOTSTRAP,
    transactional_id=f"l8-txid-{TAG}-{int(time.time())}",
    enable_idempotence=True,
    acks="all",
    max_block_ms=30000,
    request_timeout_ms=30000,
)
print(f"  transactional_id = {p.config['transactional_id']}")

try:
    # 注意：kafka-python 3.0.11 的四个事务方法【均无参数】，
    # 超时靠 max_block_ms 控制（docstring 明说 "before expiration of max_block_ms"）；
    # confluent-kafka 则是 init_transactions(timeout=...)。这是两库 API 差异点之一。
    p.init_transactions()
    print("  init_transactions  -> OK")
except Exception as e:
    print(f"  init_transactions  -> {type(e).__name__}: {str(e)[:120]}")
    sys.exit(1)

try:
    p.begin_transaction()
    for i in range(5):
        f = p.send(topic, value=f"msg-{i}".encode(), key=f"k{i}".encode())
        f.get(timeout=10)
    print("  发送 5 条 -> OK")
except Exception as e:
    print(f"  发送      -> {type(e).__name__}: {str(e)[:150]}")
    sys.exit(1)

if TAG == "commit":
    try:
        p.commit_transaction()
        print("  commit_transaction -> OK")
    except Exception as e:
        print(f"  commit_transaction -> {type(e).__name__}: {str(e)[:150]}")
        sys.exit(1)
else:
    try:
        p.abort_transaction()
        print("  abort_transaction  -> OK")
    except Exception as e:
        print(f"  abort_transaction  -> {type(e).__name__}: {str(e)[:150]}")
        sys.exit(1)
p.close()
time.sleep(1)

# 分别用两种隔离级别读，验证 abort 的消息是否真的不可见
for iso in ("read_uncommitted", "read_committed"):
    c = KafkaConsumer(topic, bootstrap_servers=BOOTSTRAP,
                      auto_offset_reset="earliest",
                      isolation_level=iso,
                      consumer_timeout_ms=8000,
                      group_id=None, enable_auto_commit=False)
    n = 0
    for _ in c:
        n += 1
    c.close()
    print(f"  isolation_level={iso:<18} 读到 {n} 条")
PYEOF

for T in commit abort; do
  echo "===== kafka-python 3.0.11 事务 $T ====="
  docker run --rm --network $NET -v "$SRC":/app/scripts -v /tmp/tx1.py:/t.py \
    -e PYTHONPATH=/app/scripts kafka-pybench:3.12 \
    /app/.venv/bin/python /t.py $T 2>&1 \
    | grep -v -e 'rdkafka#' -e 'Unclosed' | head -14
done
