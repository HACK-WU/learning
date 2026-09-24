"""课 5 复验：独立进程 + 严格判定（修正上一版判定 bug）。

上版 bug：判定写成 len(set(flat))==4，
         对 [(0,1),(2,),(2,),(3,)] 这种【有重复有缺失】的情况也返回 True。
         set 去重后恰好 4 个不同值就误判为"无重叠"。

正确判定：len(flat)==分区数 且 len(set(flat))==len(flat)
"""
import socket
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
T = "l5-verify2"
G = "l5-verify2-g"
NP = 4
IDX = int(sys.argv[1]) if len(sys.argv) > 1 else 0
LIFE = int(sys.argv[2]) if len(sys.argv) > 2 else 28

if IDX == 0:
    # 主控：建 topic + 发数据
    a = KafkaAdminClient(bootstrap_servers=BS, request_timeout_ms=15000)
    try:
        a.delete_topics([T])
        time.sleep(1)
    except Exception:
        pass
    try:
        r = a.create_topics([NewTopic(T, num_partitions=NP,
                                      replication_factor=1)])
        print("create:", [(x.get("name"), x.get("error_code"))
                          for x in r.get("topics", [])], flush=True)
    except Exception as e:
        print("create:", type(e).__name__, str(e)[:60], flush=True)
    time.sleep(1)
    p = KafkaProducer(bootstrap_servers=BS, max_block_ms=15000, acks=1)
    for i in range(40):
        p.send(T, f"v-{i:02d}".encode())
    p.flush(timeout=20)
    p.close()
    print(f"已发 40 条到 {T}（{NP} 分区）", flush=True)
    a.close()
else:
    # 消费者进程
    c = KafkaConsumer(bootstrap_servers=BS, group_id=G,
                      auto_offset_reset="earliest",
                      enable_auto_commit=False,
                      session_timeout_ms=45000,
                      heartbeat_interval_ms=3000,
                      client_id=f"v{IDX}")
    c.subscribe([T])
    t0 = time.time()
    hist = []
    while time.time() - t0 < LIFE:
        c.poll(timeout_ms=1000, max_records=5)
        a = tuple(sorted(tp.partition for tp in c.assignment()))
        hist.append((int(time.time() - t0), a))
        time.sleep(0.5)
    final = hist[-1][1] if hist else ()
    # 稳定判定：最后 5 次采样都一致
    last5 = [h[1] for h in hist[-5:]]
    stable = len(set(last5)) == 1
    print(f"CONSUMER#{IDX} final={final} stable={stable}", flush=True)
    print(f"  trajectory={[h for h in hist[::6]]}", flush=True)
    c.close()
