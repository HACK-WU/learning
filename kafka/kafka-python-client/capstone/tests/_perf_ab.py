"""对照实验 v2（修正上轮两个设计缺陷）：
  缺陷1 没灌消息 —— topic 已被上轮消费光，4 组都拿到 0 条
  缺陷2 共用 group.id —— 与服务进程抢分区，只分到 2 个

修正：
  - 预灌 N*4 条到独立 topic
  - 每组用 **独立 group.id** + earliest，从头消费，互不干扰
"""
import json
import sys
import time

sys.path.insert(0, "/app/capstone")
from app import config  # noqa: E402
from app.kafka_client import build_consumer, collect_lag, ensure_topics  # noqa: E402
from app.schema import OrderEvent  # noqa: E402
from app.worker import default_process  # noqa: E402
from confluent_kafka import Producer, Consumer  # noqa: E402
from confluent_kafka.admin import AdminClient, NewTopic  # noqa: E402

print("=" * 74)
print("课13 · 消费性能对照实验 v2")
print("=" * 74)

N = 300
TOTAL = N * 5
TOPIC = "capstone-perf"
a = AdminClient({"bootstrap.servers": config.BROKERS})
ex = set(a.list_topics(timeout=10).topics)
if TOPIC not in ex:
    for t, f in a.create_topics([NewTopic(TOPIC, num_partitions=4, replication_factor=1)]).items():
        f.result()
    print(f"\n  建 topic {TOPIC}")
else:
    print(f"\n  topic {TOPIC} 已存在")

# 预灌
p = Producer({"bootstrap.servers": config.BROKERS, "linger.ms": 5})
t0 = time.time()
for i in range(TOTAL):
    p.produce(TOPIC, json.dumps({"order_id": f"p{i:05d}", "user_id": f"u{i%50}",
                                 "amount": 10.0 + i, "currency": "CNY"}).encode())
p.flush(15)
print(f"  预灌 {TOTAL} 条，耗时 {time.time()-t0:.2f}s")


def run(label, do_commit, do_lag, lag_every=5.0):
    gid = f"perf-{label[0]}-{int(time.time()*1000)%100000}"
    c = Consumer({"bootstrap.servers": config.BROKERS, "group.id": gid,
                  "auto.offset.reset": "earliest", "enable.auto.commit": False,
                  "session.timeout.ms": 45000})
    c.subscribe([TOPIC])
    for _ in range(20):
        c.poll(1.0)
        if len(c.assignment()) == 4:
            break
    parts = len(c.assignment())
    n = 0
    t_lag = 0.0
    last = time.time()
    t0 = time.time()
    while n < N and time.time() - t0 < 60:
        msg = c.poll(timeout=1.0)
        if msg is None or msg.error():
            if do_lag and time.time() - last >= lag_every:
                ts = time.time(); collect_lag(c, TOPIC); t_lag += time.time() - ts
                last = time.time()
            continue
        n += 1
        try:
            default_process(OrderEvent.from_json(msg.value()))
        except Exception:
            pass
        if do_commit:
            c.commit(message=msg, asynchronous=False)
        if do_lag and time.time() - last >= lag_every:
            ts = time.time(); collect_lag(c, TOPIC); t_lag += time.time() - ts
            last = time.time()
    el = time.time() - t0
    rate = n / el if el > 0 else 0
    print(f"  {label:<32}{n:>4}条 {el:>7.2f}s {rate:>9.1f}/s 分区={parts} lag耗时={t_lag:>6.2f}s")
    c.close()
    return rate


print(f"\n  每组目标 {N} 条（独立 group）\n")
rA = run("A纯poll+解析", False, False)
rB = run("B+每条同步commit", True, False)
rC = run("C+每5秒collect_lag", False, True)
rD = run("D全开(当前worker)", True, True)

print(f"\n  {'配置':<28}{'速率':>12}{'相对A':>10}")
print(f"  {'-'*50}")
for name, r in (("A 纯poll+解析", rA), ("B +同步commit", rB),
                ("C +lag采集", rC), ("D 全开", rD)):
    rel = f"{r/rA:.2f}x" if rA > 0 else "n/a"
    print(f"  {name:<26}{r:>10.1f}/s{rel:>10}")

print(f"\n  判据：")
print(f"    B 明显慢于 A -> 同步 commit 是主因 -> 改批量异步提交")
print(f"    C 明显慢于 A -> lag 采集是主因   -> 降频 / 独立线程")
print(f"    D ≈ A        -> 瓶颈在别处")
