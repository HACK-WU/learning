#!/bin/bash
# 反证：linger 在什么条件下【真的】能提吞吐？
#
# 上一轮诊断（diag_linger.sh）的结论：
#   瞬间灌入 5 万条时，linger 越大吞吐越低 —— 因为瓶颈不在攒批，
#   linger 只是纯加等待延迟。
#
# 教科书"调大 linger 提吞吐"的前提是：
#   消息产生速度【慢于】攒批速度，即每条消息之间本来就有间隔。
#   此时 linger 能把"间隔期本会浪费的等待"用来攒批。
#
# 本脚本构造慢速生产（每条之间 sleep），验证该前提。
set -u
SRC=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
NET=stage6-observability_kafka-net

cat > /tmp/slow.py <<'PYEOF'
import sys, time, json
from confluent_kafka import Producer
from confluent_kafka.admin import AdminClient, NewTopic
from common import BOOTSTRAP, payload

LINGER = int(sys.argv[1])      # linger.ms
GAP_US = int(sys.argv[2])      # 每条消息之间的间隔（微秒）
N = int(sys.argv[3])
topic = f"slow-l{LINGER}-g{GAP_US}"

adm = AdminClient({"bootstrap.servers": BOOTSTRAP})
if topic in adm.list_topics(timeout=10).topics:
    fs = adm.delete_topics([topic], operation_timeout=15)
    fs[topic].result(); time.sleep(1)
adm.create_topics([NewTopic(topic, num_partitions=6, replication_factor=3)],
                  operation_timeout=15)[topic].result()
time.sleep(2)

p = Producer({
    "bootstrap.servers": BOOTSTRAP, "acks": "all",
    "linger.ms": LINGER, "batch.size": 64*1024,
    "compression.type": "none",
    "queue.buffering.max.messages": N*2,
})
n = [0]
def cb(err, msg):
    if err: raise RuntimeError(err)
    n[0] += 1

t0 = time.perf_counter()
for i in range(N):
    p.produce(topic, value=payload(i), callback=cb)
    p.poll(0)
    if GAP_US:
        time.sleep(GAP_US / 1e6)
p.flush()
el = time.perf_counter() - t0
theoretical_min = N * GAP_US / 1e6
print(f"RESULT slow linger={LINGER}ms gap={GAP_US}us "
      f"throughput={N/el:.0f} msg/s elapsed={el*1000:.0f}ms "
      f"理论下限={theoretical_min*1000:.0f}ms "
      f"batch_avg={'-'}")
PYEOF

echo "=== 场景：每条间隔 200us（模拟真实业务逐条产生，约 5000 msg/s 上限）==="
for L in 0 10 50; do
docker run --rm --network $NET -v "$SRC":/app/scripts -v /tmp/slow.py:/s.py \
  -e PYTHONPATH=/app/scripts kafka-pybench:3.12 \
  /app/.venv/bin/python /s.py $L 200 5000 2>&1 \
  | grep -v -e 'rdkafka#' -e 'Unclosed' | head -3
done

echo ""
echo "=== 对照：瞬间灌入（无间隔），同样三档 linger ==="
for L in 0 10 50; do
docker run --rm --network $NET -v "$SRC":/app/scripts -v /tmp/slow.py:/s.py \
  -e PYTHONPATH=/app/scripts kafka-pybench:3.12 \
  /app/.venv/bin/python /s.py $L 0 50000 2>&1 \
  | grep -v -e 'rdkafka#' -e 'Unclosed' | head -3
done
