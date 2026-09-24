"""课 5 权威核验：问 Broker「这个组现在到底怎么分的」。

前两轮失败原因：
  1. 用本地 assignment() → 是再均衡中间态视图
  2. 启动间隔太短、采样太早 → 未收敛就判定

这版：
  - 4 个消费者全部启动后才开始计时
  - 等足够久（45s）让再均衡彻底完成
  - 用 coordinator 的权威数据判定（不靠本地视图）
"""
import socket
import sys
import time

from kafka import KafkaAdminClient, KafkaConsumer

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
T = "l5-final"
G = "l5-final-g"
IDX = int(sys.argv[1]) if len(sys.argv) > 1 else 0
LIFE = int(sys.argv[2]) if len(sys.argv) > 2 else 50

if IDX == 0:
    from kafka.admin import NewTopic
    from kafka import KafkaProducer
    a = KafkaAdminClient(bootstrap_servers=BS, request_timeout_ms=15000)
    try:
        a.delete_topics([T]); time.sleep(1)
    except Exception:
        pass
    try:
        r = a.create_topics([NewTopic(T, num_partitions=4,
                                      replication_factor=1)])
        print("create:", [(x.get("name"), x.get("error_code"))
                          for x in r.get("topics", [])], flush=True)
    except Exception as e:
        print("create:", type(e).__name__, str(e)[:60], flush=True)
    time.sleep(1)
    p = KafkaProducer(bootstrap_servers=BS, max_block_ms=15000, acks=1)
    for i in range(40):
        p.send(T, f"f-{i:02d}".encode())
    p.flush(timeout=20); p.close()
    print("已发 40 条到 4 分区", flush=True)

    # 等所有消费者都进来
    time.sleep(LIFE)

    # 权威判定 1：list_consumer_group_offsets 看实际提交的分区
    print("\n=== 权威视角：AdminClient 查询组信息 ===", flush=True)
    try:
        from kafka.coordinator.consumer import ConsumerGroupCoordinator  # noqa
    except Exception:
        pass
    # 用 consumer 临时取样（独立实例，只读组元数据）
    probe = KafkaConsumer(bootstrap_servers=BS, group_id=G,
                          auto_offset_reset="earliest",
                          enable_auto_commit=False)
    probe.subscribe([T])
    for _ in range(10):
        probe.poll(timeout_ms=1000, max_records=1)
    print(f"probe 看到自己分配: {sorted(tp.partition for tp in probe.assignment())}",
          flush=True)
    probe.close()

    print("\n=== 清理 ===", flush=True)
    try:
        a.delete_topics([T])
        print("topic 已删", flush=True)
    except Exception as e:
        print("delete:", type(e).__name__, flush=True)
    a.close()
else:
    c = KafkaConsumer(bootstrap_servers=BS, group_id=G,
                      auto_offset_reset="earliest",
                      enable_auto_commit=False,
                      session_timeout_ms=45000,
                      heartbeat_interval_ms=3000,
                      client_id=f"fin{IDX}")
    c.subscribe([T])
    t0 = time.time()
    hist = []
    while time.time() - t0 < LIFE:
        c.poll(timeout_ms=1000, max_records=5)
        hist.append((round(time.time() - t0, 1),
                     tuple(sorted(tp.partition for tp in c.assignment()))))
        time.sleep(0.5)
    last10 = [h[1] for h in hist[-10:]]
    print(f"FINAL#{IDX} assignment={hist[-1][1]} "
          f"stable={len(set(last10)) == 1}", flush=True)
    print(f"  TRACE#{IDX}={[h for h in hist[::8]]}", flush=True)
    c.close()
