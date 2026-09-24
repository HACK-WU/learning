#!/bin/bash
# 诊断：为什么 kafka-python 开压缩后吞吐反而涨 4 倍（7777 → 28000+）？
#
# 假设：
#   H1 网络瓶颈——1KB×50000 = 50MB 走 localhost 网络，压缩后字节数骤减，
#      纯 Python 客户端的瓶颈本来就在网络/IO 而不是 CPU
#   H2 CPU 瓶颈——若如此，压缩应【降低】吞吐，与实测相反，可排除
#   H3 序列化开销被摊薄——不成立，压缩是【增加】CPU 工作
#
# 验证手法：固定消息条数，只改【消息体大小】，看吞吐是否随字节数成比例变化。
#   若吞吐 ∝ 1/字节数 → 瓶颈在网络带宽（H1 成立）
#   若吞吐几乎不变   → 瓶颈在 CPU/序列化（H2 成立）
set -u
SRC=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
NET=stage6-observability_kafka-net

cat > /tmp/sz.py <<'PYEOF'
import sys, time
from kafka import KafkaProducer
from kafka.admin import KafkaAdminClient, NewTopic
from common import BOOTSTRAP, MSG_SIZE, NUM_MESSAGES, payload

LIBTAG = sys.argv[1]      # "kp" 或 "cf"
SIZE = int(sys.argv[2])
topic = f"sz-{LIBTAG}-{SIZE}"

adm = KafkaAdminClient(bootstrap_servers=BOOTSTRAP, request_timeout_ms=15000)
try:
    adm.delete_topics([topic], timeout_ms=15000); time.sleep(1)
except Exception:
    pass
try:
    adm.create_topics([NewTopic(topic, num_partitions=6, replication_factor=3)],
                      timeout_ms=15000)
except Exception:
    pass
adm.close()
time.sleep(2)

if LIBTAG == "kp":
    p = KafkaProducer(bootstrap_servers=BOOTSTRAP, acks="all",
                      compression_type=None, linger_ms=10,
                      batch_size=64*1024, max_block_ms=60000)
    n = [0]
    t0 = time.perf_counter()
    for i in range(NUM_MESSAGES):
        # 用 SIZE 覆盖 common.payload 的固定 1KB
        body = b'{"seq":%d,"pad":"' % i
        p.send(topic, value=(body + b"x"*(SIZE-len(body)-2) + b'"}')[:SIZE])
    p.flush()
    el = time.perf_counter() - t0
    p.close()
else:
    from confluent_kafka import Producer as CP
    p = CP({"bootstrap.servers": BOOTSTRAP, "acks": "all",
            "linger.ms": 10, "batch.size": 64*1024,
            "compression.type": "none",
            "queue.buffering.max.messages": NUM_MESSAGES*2})
    t0 = time.perf_counter()
    for i in range(NUM_MESSAGES):
        body = b'{"seq":%d,"pad":"' % i
        p.produce(topic, value=(body + b"x"*(SIZE-len(body)-2) + b'"}')[:SIZE])
        p.poll(0)
    p.flush()
    el = time.perf_counter() - t0

mb = NUM_MESSAGES * SIZE / 1024 / 1024
print(f"RESULT size {LIBTAG} msg={SIZE}B n={NUM_MESSAGES} "
      f"throughput={NUM_MESSAGES/el:.0f} msg/s  MBps={mb/el:.2f}")
PYEOF

for LIBTAG in kp cf; do
  echo "=== $LIBTAG ==="
  for S in 128 1024 8192; do
    docker run --rm --network $NET -v "$SRC":/app/scripts -v /tmp/sz.py:/s.py \
      -e PYTHONPATH=/app/scripts -e NUM_MESSAGES=20000 kafka-pybench:3.12 \
      /app/.venv/bin/python /s.py $LIBTAG $S 2>&1 \
      | grep -v -e 'rdkafka#' -e 'Unclosed' | head -2
  done
done
