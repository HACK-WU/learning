#!/bin/bash
# 诊断：为什么 linger 越大吞吐越低？（与教科书相反，必须查根因而不是只报数字）
#
# 假设：
#   H1 测量假象——produce() 是异步的，linger 大时消息积压在本地队列，
#      flush() 才真正发完，若计时终点取错会失真
#   H2 真实瓶颈——本 bench 的消息产生速度（Python 循环）跟不上，
#      linger 等待期间队列空转，反而拉长了总耗时
#   H3 broker 侧——批量变大导致单请求处理变慢
set -u
SRC=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
NET=stage6-observability_kafka-net

cat > /tmp/diag.py <<'PYEOF'
import sys, time, json
from confluent_kafka import Producer
from confluent_kafka.admin import AdminClient, NewTopic
from common import BOOTSTRAP, NUM_MESSAGES, payload

LINGER = int(sys.argv[1])
topic = f"diag-l{LINGER}"

adm = AdminClient({"bootstrap.servers": BOOTSTRAP})
if topic in adm.list_topics(timeout=10).topics:
    fs = adm.delete_topics([topic], operation_timeout=15)
    fs[topic].result(); time.sleep(2)
adm.create_topics([NewTopic(topic, num_partitions=6, replication_factor=3)],
                  operation_timeout=15)[topic].result()
time.sleep(2)

stats = {}
def on_stats(s):
    d = json.loads(s)
    stats['brokers'] = d.get('brokers', {})

p = Producer({
    "bootstrap.servers": BOOTSTRAP,
    "acks": "all",
    "linger.ms": LINGER,
    "batch.size": 64*1024,
    "compression.type": "none",
    "queue.buffering.max.messages": NUM_MESSAGES*2,
    "statistics.interval.ms": 500,
    "stats_cb": on_stats,
})

delivered = [0]
def cb(err, msg):
    if err: raise RuntimeError(err)
    delivered[0] += 1

t_send0 = time.perf_counter()
for i in range(NUM_MESSAGES):
    p.produce(topic, value=payload(i), callback=cb)
    p.poll(0)
t_send_done = time.perf_counter()

# 分区时刻：produce 循环结束 / flush 结束
t_flush0 = time.perf_counter()
p.flush()
t_flush_done = time.perf_counter()

send_elapsed = t_send_done - t_send0
flush_elapsed = t_flush_done - t_flush0
total = t_flush_done - t_send0

print(f"RESULT diag linger={LINGER}ms")
print(f"  produce 循环耗时   = {send_elapsed*1000:>8.0f} ms  （Python 侧投递 {NUM_MESSAGES} 条）")
print(f"  flush 等待耗时     = {flush_elapsed*1000:>8.0f} ms  （等 broker 确认积压消息）")
print(f"  总耗时             = {total*1000:>8.0f} ms")
print(f"  含 flush 的吞吐    = {NUM_MESSAGES/total:>8.0f} msg/s")
print(f"  不含 flush 的吞吐  = {NUM_MESSAGES/send_elapsed:>8.0f} msg/s  ← 若二者差异大，说明消息积压在本地队列")
print(f"  确认条数           = {delivered[0]}")
PYEOF

for L in 0 10 100; do
docker run --rm --network $NET -v "$SRC":/app/scripts -v /tmp/diag.py:/d.py \
  -e NUM_MESSAGES=50000 -e PYTHONPATH=/app/scripts kafka-pybench:3.12 \
  /app/.venv/bin/python /d.py $L 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed' | head -12
done
