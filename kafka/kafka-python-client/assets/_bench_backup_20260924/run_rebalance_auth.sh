#!/bin/bash
# 课 5：4 个独立进程消费者 + Broker 权威视角核验
set -u
NET=stage6-observability_kafka-net
W=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
IMG=python:3.12-slim
T=l5-rb-auth
G=l5-auth-group

# 1. 建 topic + 发数据
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
a=KafkaAdminClient(bootstrap_servers=BS, request_timeout_ms=15000)
try:
    r=a.create_topics([NewTopic("l5-rb-auth", num_partitions=4, replication_factor=1)])
    print("create:", [(x.get("name"), x.get("error_code")) for x in r.get("topics",[])])
except Exception as e: print("create:", type(e).__name__)
time.sleep(1)
p=KafkaProducer(bootstrap_servers=BS, max_block_ms=15000, acks=1)
for i in range(40): p.send("l5-rb-auth", f"x-{i:02d}".encode())
p.flush(timeout=20); p.close(); print("已发 40 条")
a.close()
PY' 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed'

echo ""
echo "########## 启动 4 个独立进程消费者（各存活 30s） ##########"
for i in 1 2 3 4; do
  docker run -d --name "l5c$i" --network "$NET" -v "$W:/w" "$IMG" \
    bash -c "pip install -q kafka-python==3.0.11 >/dev/null 2>&1
      python /w/verify_rebalance_auth.py $i 30" >/dev/null 2>&1
  echo "  启动 consumer #$i"
  sleep 6
done

echo ""
echo "########## Broker 权威视角：describe consumer group ##########"
sleep 8
docker exec l15-kafka-1 /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --describe --group "$G" 2>/dev/null

echo ""
echo "########## 各消费者自报 assignment ##########"
for i in 1 2 3 4; do
  echo "  --- consumer #$i ---"
  docker logs "l5c$i" 2>/dev/null | grep -E 'assignment=|结束' | tail -3
done

echo ""
echo "########## 清理 ##########"
for i in 1 2 3 4; do docker rm -f "l5c$i" >/dev/null 2>&1; done
docker exec l15-kafka-1 /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --delete --topic "$T" 2>/dev/null
echo "  已清理"
