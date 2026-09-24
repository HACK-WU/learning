"""课 5：用 Broker 权威视角核验分区分配。

上一版用 consumer.assignment()（本地视图）得到「分区 2 被两个消费者持有」的
荒谬结果 —— Kafka 不可能这样，说明本地视图不可信。

这版：用 AdminClient 的 list_consumer_group_offsets / describe 或者
     直接查 __consumer_offsets，拿 coordinator 的真实分配。

更可靠：跑 4 个【独立进程】的消费者，然后用 CLI 查 group 状态。
"""
import socket
import subprocess
import sys
import time

from kafka import KafkaAdminClient, KafkaConsumer, KafkaProducer
from kafka.admin import NewTopic

HOSTS = ["kafka-1", "kafka-2", "kafka-3"]
BS_LIST = []
for h in HOSTS:
    try:
        ip = socket.gethostbyname(h)
        s = socket.socket()
        s.settimeout(3)
        s.connect((ip, 9092))
        BS_LIST.append(f"{h}:9092")
        s.close()
    except OSError:
        pass
BS = ",".join(BS_LIST)
T = "l5-rb-auth"
G = "l5-auth-group"
IDX = int(sys.argv[1]) if len(sys.argv) > 1 else 0     # 本消费者编号
LIFE = int(sys.argv[2]) if len(sys.argv) > 2 else 25   # 存活秒数

print(f"=== consumer #{IDX} 启动，group={G}, 存活 {LIFE}s ===")
c = KafkaConsumer(bootstrap_servers=BS, group_id=G,
                  auto_offset_reset="earliest",
                  enable_auto_commit=False,
                  session_timeout_ms=45000,
                  heartbeat_interval_ms=3000,
                  client_id=f"cons-{IDX}")
c.subscribe([T])

t0 = time.time()
n = 0
while time.time() - t0 < LIFE:
    recs = c.poll(timeout_ms=1000, max_records=10)
    n += sum(len(v) for v in recs.values())
    parts = sorted(tp.partition for tp in c.assignment())
    if int(time.time() - t0) % 5 == 0:
        print(f"  #{IDX} t={int(time.time()-t0):>2}s assignment={parts} 累计收{n}条",
              flush=True)
    time.sleep(0.5)

print(f"=== consumer #{IDX} 结束: 最终 assignment="
      f"{sorted(tp.partition for tp in c.assignment())}, 共收 {n} 条 ===")
c.close()
