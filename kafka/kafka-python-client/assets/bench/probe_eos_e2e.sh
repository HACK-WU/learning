#!/bin/bash
# 课 8 核心实测①：consume-transform-produce 全链路 EOS
# 这才是"恰好一次"的完整形态：读->处理->写->提交offset，四步原子
set -u
SRC=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
NET=stage6-observability_kafka-net

cat /tmp/eos.py > /dev/null 2>&1 <<'X'
X
cat > /tmp/eos.py <<'PYEOF'
import sys, time
from kafka import KafkaProducer, KafkaConsumer, OffsetAndMetadata
from kafka.admin import KafkaAdminClient, NewTopic
from common import BOOTSTRAP

LIB = sys.argv[1]          # kp | cf
SRC_T = "l8-eos-src"
DST_T = "l8-eos-dst"
GROUP = f"l8-eos-g-{int(time.time())}"
TXID = f"l8-eos-tx-{int(time.time())}"

adm = KafkaAdminClient(bootstrap_servers=BOOTSTRAP, request_timeout_ms=15000)
for t in (SRC_T, DST_T):
    try: adm.delete_topics([t], timeout_ms=15000); time.sleep(1)
    except Exception: pass
for t in (SRC_T, DST_T):
    try: adm.create_topics([NewTopic(t, num_partitions=3, replication_factor=1)], timeout_ms=15000)
    except Exception: pass
adm.close(); time.sleep(2)

# 1) 先灌 10 条源数据
pp = KafkaProducer(bootstrap_servers=BOOTSTRAP, acks="all", max_block_ms=20000)
for i in range(10):
    pp.send(SRC_T, value=f"raw-{i}".encode(), key=str(i).encode())
pp.flush(); pp.close()
time.sleep(1)
print(f"  源 topic 已灌入 10 条")

if LIB == "kp":
    p = KafkaProducer(bootstrap_servers=BOOTSTRAP, transactional_id=TXID,
                      enable_idempotence=True, acks="all", max_block_ms=30000)
    p.init_transactions()
    c = KafkaConsumer(SRC_T, bootstrap_servers=BOOTSTRAP, group_id=GROUP,
                      auto_offset_reset="earliest", enable_auto_commit=False,
                      isolation_level="read_committed",
                      consumer_timeout_ms=10000, max_poll_records=500)
    n = 0
    while True:
        batch = c.poll(timeout_ms=5000, max_records=500)
        if not batch:
            break
        try:
            p.begin_transaction()
            for tp, msgs in batch.items():
                for m in msgs:
                    p.send(DST_T, value=m.value.upper(), key=m.key)
                    n += 1
            # 关键一步：把消费 offset 纳入事务
            # 关键一步：把消费 offset 纳入事务。
            # 注意：kafka-python 的 group_metadata 是【方法】要加括号调用，
            # 返回 ConsumerGroupMetadata(group_id, generation_id, member_id,
            #        group_instance_id, state) 具名元组；写成属性会传成
            # bound method，触发 TypeError。confluent 侧则是属性
            # c.consumer_group_metadata()。
            p.send_offsets_to_transaction(
                {tp: OffsetAndMetadata(msgs[-1].offset + 1, None)
                 for tp, msgs in batch.items()},
                c.group_metadata())
            p.commit_transaction()
            print(f"  事务提交：处理 {n} 条，offset 已纳入事务")
        except Exception as e:
            p.abort_transaction()
            print(f"  事务回滚: {type(e).__name__}: {str(e)[:100]}")
            break
    c.close(); p.close()
else:
    from confluent_kafka import Producer as CP, Consumer as CC
    p = CP({"bootstrap.servers": BOOTSTRAP, "transactional.id": TXID,
            "enable.idempotence": True, "acks": "all",
            "transaction.timeout.ms": 60000})
    p.init_transactions()
    c = CC({"bootstrap.servers": BOOTSTRAP, "group.id": GROUP,
            "auto.offset.reset": "earliest", "enable.auto.commit": False,
            "isolation.level": "read_committed"})
    c.subscribe([SRC_T])
    n = 0
    for _ in range(5):
        msgs = c.consume(500, timeout=5.0)
        if not msgs:
            break
        try:
            p.begin_transaction()
            for m in msgs:
                if m.error():
                    continue
                p.produce(DST_T, value=m.value().upper(), key=m.key())
                n += 1
            p.send_offsets_to_transaction(
                c.position(c.assignment()), c.consumer_group_metadata())
            p.commit_transaction()
            print(f"  事务提交：处理 {n} 条，offset 已纳入事务")
        except Exception as e:
            p.abort_transaction()
            print(f"  事务回滚: {type(e).__name__}: {str(e)[:100]}")
            break
    c.close(); p.flush()

time.sleep(1)
# 2) 验证：目标 topic 条数应等于 10，无重复
cc = KafkaConsumer(DST_T, bootstrap_servers=BOOTSTRAP, group_id=None,
                   auto_offset_reset="earliest", enable_auto_commit=False,
                   isolation_level="read_committed", consumer_timeout_ms=8000)
vals = [m.value.decode() for m in cc]
cc.close()
print(f"  >>> 目标 topic 实际 {len(vals)} 条，去重后 {len(set(vals))} 条")
print(f"      {sorted(vals)}")
PYEOF

for L in kp cf; do
  echo "===== consume-transform-produce EOS [$L] ====="
  docker run --rm --network $NET -v "$SRC":/app/scripts -v /tmp/eos.py:/e.py \
    -e PYTHONPATH=/app/scripts kafka-pybench:3.12 \
    /app/.venv/bin/python /e.py $L 2>&1 \
    | grep -v -e 'rdkafka#' -e 'Unclosed' | head -12
done
