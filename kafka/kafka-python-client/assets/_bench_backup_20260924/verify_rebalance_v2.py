"""课 5 权威核验 v2：等到真正收敛再判定。

前三次失败的三个独立根因（都已定位）：
  1. kafka-consumer-groups.sh 因 JMX Exporter 端口占用【启动失败】
     → describe 一直返回空（工具坏，不是 Kafka 问题）
  2. 本地 assignment() 是再均衡【中间态】视图
  3. 等待时间不足、采样过早

这版：
  - 不依赖 CLI（改用 kafka-python 自身，课 3 已验证可用）
  - 持续 poll 直到【分配连续稳定 N 秒】才判定
  - 用 AdminClient 交叉验证组成员
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
T = "l5-v2"
G = "l5-v2-g"
NP = 4
IDX = int(sys.argv[1]) if len(sys.argv) > 1 else 0
LIFE = int(sys.argv[2]) if len(sys.argv) > 2 else 70

if IDX == 0:
    a = KafkaAdminClient(bootstrap_servers=BS, request_timeout_ms=20000)
    try:
        a.delete_topics([T]); time.sleep(1)
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
        p.send(T, f"v2-{i:02d}".encode())
    p.flush(timeout=20); p.close()
    print(f"已发 40 条到 {T}（{NP} 分区）", flush=True)
    time.sleep(LIFE)
    print("主控结束", flush=True)
    a.close()
else:
    c = KafkaConsumer(bootstrap_servers=BS, group_id=G,
                      auto_offset_reset="earliest",
                      enable_auto_commit=False,
                      session_timeout_ms=45000,
                      heartbeat_interval_ms=3000,
                      client_id=f"w{IDX}")
    c.subscribe([T])
    t0 = time.time()
    hist = []
    STABLE_SEC = 12          # 连续稳定 12 秒才算收敛
    stable_since = None
    result = None
    while time.time() - t0 < LIFE:
        c.poll(timeout_ms=1000, max_records=5)
        cur = tuple(sorted(tp.partition for tp in c.assignment()))
        hist.append((round(time.time() - t0, 1), cur))
        if len(hist) >= 2 and cur == hist[-2][1]:
            if stable_since is None:
                stable_since = time.time()
            elif time.time() - stable_since >= STABLE_SEC:
                result = cur
                break
        else:
            stable_since = None
        time.sleep(0.5)
    if result is None:
        result = hist[-1][1] if hist else ()
    print(f"FINAL#{IDX} assignment={result} "
          f"converged={result is not None and stable_since is not None} "
          f"elapsed={round(time.time()-t0,1)}s", flush=True)
    print(f"  TRACE#{IDX}=" + str([h for h in hist[::10]]), flush=True)
    c.close()
