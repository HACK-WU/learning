#!/bin/bash
# 补测：每1条一事务（小样本）+ confluent 四档完整对照
# 上一轮教训：每1条一事务在 20000 条规模下需 20 万秒，跑不完。
# 铁律：先探路再立项 —— 先小样本探出量级，再决定正式规模。
set -u
SRC=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
NET=stage6-observability_kafka-net

cat > /tmp/one.py <<'PYEOF'
import sys, time
from common import BOOTSTRAP, payload
LIB = sys.argv[1]; N = int(sys.argv[2])
T = f"l8-one-{LIB}"
def reset():
    from kafka.admin import KafkaAdminClient, NewTopic
    a = KafkaAdminClient(bootstrap_servers=BOOTSTRAP, request_timeout_ms=15000)
    try: a.delete_topics([T], timeout_ms=15000); time.sleep(1)
    except Exception: pass
    try: a.create_topics([NewTopic(T, num_partitions=6, replication_factor=3)], timeout_ms=15000)
    except Exception: pass
    a.close(); time.sleep(2)
reset()
if LIB == "kp":
    from kafka import KafkaProducer
    p = KafkaProducer(bootstrap_servers=BOOTSTRAP, acks="all",
                      enable_idempotence=True, linger_ms=0, max_block_ms=60000,
                      transactional_id=f"l8-one-tx-{int(time.time())}")
    p.init_transactions()
    t0 = time.perf_counter()
    for i in range(N):
        p.begin_transaction()
        p.send(T, value=payload(i))
        p.commit_transaction()
    el = time.perf_counter() - t0
    p.close()
else:
    from confluent_kafka import Producer as CP
    p = CP({"bootstrap.servers": BOOTSTRAP, "acks": "all",
            "enable.idempotence": True, "linger.ms": 0,
            "queue.buffering.max.messages": N*2,
            "transactional.id": f"l8-one-tx-{int(time.time())}",
            "transaction.timeout.ms": 60000})
    p.init_transactions()
    t0 = time.perf_counter()
    for i in range(N):
        p.begin_transaction()
        p.produce(T, value=payload(i)); p.poll(0)
        p.commit_transaction()
    el = time.perf_counter() - t0
print(f"RESULT one {LIB} 每1条一事务(N={N}) {N/el:>8.1f} msg/s  elapsed={el*1000:.0f}ms  "
      f"单事务均摊={el/N*1000:.1f}ms")
PYEOF

for L in kp cf; do
  echo "===== 每1条一事务（小样本 N=1000）[$L] ====="
  docker run --rm --network $NET -v "$SRC":/app/scripts -v /tmp/one.py:/o.py \
    -e PYTHONPATH=/app/scripts kafka-pybench:3.12 \
    /app/.venv/bin/python /o.py $L 1000 2>&1 \
    | grep -v -e 'rdkafka#' -e 'Unclosed' | head -3
done
