#!/bin/bash
# 诊断：kafka-python 事务状态机【惰性进入 IN_TRANSACTION】？
# 现象：begin_transaction() 后不 send 直接 commit → KafkaError: Invalid transition
#       from state READY to state COMMITTING_TRANSACTION
# 假设：状态机在第一次 send 时才从 READY 转入 IN_TRANSACTION
set -u
cat > /tmp/sm.py <<'PYEOF'
from kafka import KafkaProducer
from kafka.producer.transaction_manager import TransactionState
import kafka.producer.transaction_manager as tm
from common import BOOTSTRAP
import time

TXID = f"l8-sm-{int(time.time())}"
p = KafkaProducer(bootstrap_servers=BOOTSTRAP, transactional_id=TXID,
                  enable_idempotence=True, acks="all", max_block_ms=20000)
p.init_transactions()
m = p._transaction_manager

def st(tag):
    print(f"  {tag:<34} state={m._current_state.name}")

st("init_transactions 之后")
p.begin_transaction(); st("begin_transaction 之后")
print("  --> 若此处仍是 READY，即证明状态机惰性进入")

p.send("l8-sm-topic", value=b"x")
st("send 一条之后")

p.commit_transaction(); st("commit_transaction 之后")

print("\n  === 状态机允许的状态集合 ===")
for s in TransactionState:
    print(f"    {s.name}")
PYEOF
docker run --rm --network stage6-observability_kafka-net \
  -v /mnt/d/projects/learning/kafka/kafka-python-client/assets/bench:/app/scripts \
  -v /tmp/sm.py:/s.py -e PYTHONPATH=/app/scripts kafka-pybench:3.12 \
  /app/.venv/bin/python /s.py 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed' | head -25
