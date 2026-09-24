#!/bin/bash
# 诊断：组协调器到底能不能用？最小实验（单消费者）
set -u
NET=stage6-observability_kafka-net
W=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
IMG=python:3.12-slim

echo "########## 1. 建 topic（2 分区，简化） ##########"
docker run --rm --network "$NET" -v "$W:/w" "$IMG" \
  bash -c 'pip install -q kafka-python==3.0.11 >/dev/null 2>&1
python - <<PY
import socket, time
from kafka import KafkaAdminClient, KafkaProducer
from kafka.admin import NewTopic
BS=[]
for h in ["kafka-1","kafka-2","kafka-3"]:
    try:
        ip=socket.gethostbyname(h); s=socket.socket(); s.settimeout(3)
        s.connect((ip,9092)); BS.append(f"{h}:9092"); s.close()
    except OSError: pass
BS=",".join(BS)
print("brokers:", BS)
a=KafkaAdminClient(bootstrap_servers=BS, request_timeout_ms=15000)
try:
    r=a.create_topics([NewTopic("l5-min", num_partitions=2, replication_factor=1)])
    print("create:", [(x.get("name"),x.get("error_code")) for x in r.get("topics",[])])
except Exception as e: print("create:", type(e).__name__, str(e)[:70])
time.sleep(1)
p=KafkaProducer(bootstrap_servers=BS, max_block_ms=15000, acks=1)
for i in range(20): p.send("l5-min", f"m-{i:02d}".encode())
p.flush(timeout=20); p.close(); print("已发 20 条")
a.close()
PY' 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed'

echo ""
echo "########## 2. 单消费者消费并提交（验证组协调器可用） ##########"
docker run --rm --network "$NET" -v "$W:/w" "$IMG" \
  bash -c 'pip install -q kafka-python==3.0.11 >/dev/null 2>&1
python - <<PY
import socket
from kafka import KafkaConsumer
from kafka.structs import TopicPartition
BS=[]
for h in ["kafka-1","kafka-2","kafka-3"]:
    try:
        ip=socket.gethostbyname(h); s=socket.socket(); s.settimeout(3)
        s.connect((ip,9092)); BS.append(f"{h}:9092"); s.close()
    except OSError: pass
BS=",".join(BS)
c=KafkaConsumer(bootstrap_servers=BS, group_id="l5-min-g",
    auto_offset_reset="earliest", enable_auto_commit=True,
    auto_commit_interval_ms=1000, client_id="min-1")
c.subscribe(["l5-min"])
n=0
for _ in range(20):
    r=c.poll(timeout_ms=1000, max_records=10)
    n+=sum(len(v) for v in r.values())
print("消费条数:", n, "assignment:", sorted(tp.partition for tp in c.assignment()))
import time; time.sleep(2)
c.commit()
for p in (0,1):
    print(f"  p{p} committed =", c.committed(TopicPartition("l5-min", p)))
c.close()
PY' 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed'

echo ""
echo "########## 3. Broker describe（组是否可见） ##########"
docker exec l15-kafka-1 /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --describe --group l5-min-g 2>&1 | head -10

echo ""
echo "########## 4. 列出所有组 ##########"
docker exec l15-kafka-1 /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --list 2>&1 | head -10

echo ""
echo "########## 5. 清理 ##########"
docker exec l15-kafka-1 /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --delete --topic l5-min >/dev/null 2>&1
echo "  已清理"
