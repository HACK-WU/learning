#!/bin/bash
# 课 8 核心实测③：事务的代价（吞吐）
# 四档对照：无事务 / 每100条一事务 / 每10条一事务 / 每1条一事务
# 铁律：先探路再立项，代价必须量化，不能只说"事务有开销"
set -u
SRC=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
NET=stage6-observability_kafka-net

cat > /tmp/cost.py <<'PYEOF'
import sys, time
from common import BOOTSTRAP, payload

LIB = sys.argv[1]          # kp | cf
BATCH = int(sys.argv[2])   # 0=无事务，>0=每 BATCH 条一事务
N = 20000
T = f"l8-cost-{LIB}-{BATCH}"

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
    kw = dict(bootstrap_servers=BOOTSTRAP, acks="all",
              enable_idempotence=True, linger_ms=0, max_block_ms=60000)
    if BATCH > 0:
        kw["transactional_id"] = f"l8-cost-tx-{BATCH}-{int(time.time())}"
    p = KafkaProducer(**kw)
    if BATCH > 0:
        p.init_transactions()
    t0 = time.perf_counter()
    if BATCH == 0:
        for i in range(N):
            p.send(T, value=payload(i))
        p.flush()
    else:
        p.begin_transaction()
        for i in range(N):
            p.send(T, value=payload(i))
            if (i + 1) % BATCH == 0 and i + 1 < N:
                p.commit_transaction()
                p.begin_transaction()
        p.commit_transaction()   # 提交最后一批（此时状态必为 IN_TRANSACTION）
    el = time.perf_counter() - t0
    p.close()
else:
    from confluent_kafka import Producer as CP
    cfg = {"bootstrap.servers": BOOTSTRAP, "acks": "all",
           "enable.idempotence": True, "linger.ms": 0,
           "queue.buffering.max.messages": N * 2}
    if BATCH > 0:
        cfg["transactional.id"] = f"l8-cost-tx-{BATCH}-{int(time.time())}"
        cfg["transaction.timeout.ms"] = 60000
    p = CP(cfg)
    if BATCH > 0:
        p.init_transactions()
    t0 = time.perf_counter()
    if BATCH == 0:
        for i in range(N):
            p.produce(T, value=payload(i)); p.poll(0)
        p.flush()
    else:
        p.begin_transaction()
        for i in range(N):
            p.produce(T, value=payload(i)); p.poll(0)
            if (i + 1) % BATCH == 0 and i + 1 < N:
                p.commit_transaction()
                p.begin_transaction()
        p.commit_transaction()
    el = time.perf_counter() - t0

tag = "无事务" if BATCH == 0 else f"每{BATCH}条一事务"
print(f"RESULT cost {LIB} {tag:<14} {N/el:>9.0f} msg/s  {N*1024/1024/1024/el:>6.2f} GB/s  elapsed={el*1000:.0f}ms")
PYEOF

for LIB in kp cf; do
  echo "===== 事务代价 [$LIB] ====="
  for B in 0 100 10 1; do
    docker run --rm --network $NET -v "$SRC":/app/scripts -v /tmp/cost.py:/c.py \
      -e PYTHONPATH=/app/scripts kafka-pybench:3.12 \
      /app/.venv/bin/python /c.py $LIB $B 2>&1 \
      | grep -v -e 'rdkafka#' -e 'Unclosed' | head -2
  done
done
