#!/bin/bash
# 课 10 实验③：消费端扩容天花板 —— 分区数 vs 消费者数
#
# 核心问题："消费慢，加消费者实例" 能无限扩吗？
# 答案：不能。一个分区同一时刻只能被组内一个消费者消费。
# 消费者数 > 分区数 -> 多出来的空转（idle）
set -u
cat > /tmp/l10_scale.py <<'PYEOF'
import json, time, sys
from confluent_kafka import Consumer, Producer
from confluent_kafka.admin import AdminClient, NewTopic

BOOT = "kafka-1:9092,kafka-2:9092,kafka-3:9092"
GROUP = "l10-scale-g"

def ensure_topic(topic, parts):
    a = AdminClient({"bootstrap.servers": BOOT})
    try:
        a.delete_topics([topic]); time.sleep(2)
    except Exception: pass
    try:
        a.create_topics([NewTopic(topic, num_partitions=parts, replication_factor=1)])
        time.sleep(2)
    except Exception as e:
        print(f"  create fail: {str(e)[:60]}")

def produce(topic, n):
    p = Producer({"bootstrap.servers": BOOT})
    for i in range(n):
        p.produce(topic, json.dumps({"i": i}).encode(), key=str(i).encode())
    p.flush()

print("=" * 76)
print("课 10 · 消费端扩容天花板（分区数 vs 消费者数）")
print("=" * 76)

TOPIC = "l10-scale-4p"
PARTS = 4
ensure_topic(TOPIC, PARTS)
produce(TOPIC, 400)

print(f"\nTopic: {TOPIC}, 分区数 = {PARTS}, 消息 400 条")
print(f"逐步增加消费者实例数，看每个实例分到几个分区\n")
print(f"  {'实例数':<10}{'各实例分到分区':<34}{'空转实例':<10}")
print(f"  {'-'*56}")

a = AdminClient({"bootstrap.servers": BOOT})

def run_group(n_consumers, wait=14):
    cs = []
    for i in range(n_consumers):
        c = Consumer({"bootstrap.servers": BOOT, "group.id": GROUP,
                      "auto.offset.reset": "earliest",
                      "enable.auto.commit": True,
                      "session.timeout.ms": 10000,
                      "heartbeat.interval.ms": 3000})
        c.subscribe([TOPIC]); cs.append(c)
    # 轮询足够久让 rebalance 收敛
    t0 = time.perf_counter()
    while time.perf_counter() - t0 < wait:
        for c in cs: c.poll(0.2)
    # 读各自 assignment
    assigns = []
    for c in cs:
        try:
            tp = c.assignment()
            ps = sorted(t.partition for t in tp)
        except Exception:
            ps = []
        assigns.append(ps)
    for c in cs: c.close()
    return assigns

import threading, multiprocessing as mp

def worker(idx, out):
    c = Consumer({"bootstrap.servers": BOOT, "group.id": GROUP,
                  "auto.offset.reset": "earliest", "enable.auto.commit": True,
                  "session.timeout.ms": 10000, "heartbeat.interval.ms": 3000})
    c.subscribe([TOPIC])
    t0 = time.perf_counter()
    while time.perf_counter() - t0 < 16:
        c.poll(0.3)
    try:
        ps = sorted(t.partition for t in c.assignment())
    except Exception:
        ps = []
    out[idx] = ps
    c.close()

for n in [1, 2, 4, 6]:
    mgr = mp.Manager(); out = mgr.dict()
    procs = [mp.Process(target=worker, args=(i, out)) for i in range(n)]
    for p in procs: p.start()
    for p in procs: p.join()
    assigns = [out.get(i, []) for i in range(n)]
    idle = sum(1 for x in assigns if len(x) == 0)
    shown = str([len(x) for x in assigns])
    detail = str(assigns) if n <= 4 else shown
    print(f"  {n:<10}{detail:<34}{idle if n>PARTS else 0:<10}")

print(f"\n判读:")
print(f"  · 实例数 <= 分区数({PARTS})：每个实例至少 1 个分区，加实例有效")
print(f"  · 实例数  > 分区数({PARTS})：多出来的实例 assignment 为空 —— 空转")
print(f"  · ⚠ 所以『消费慢就加实例』有硬上限，上限 = 分区数")
print(f"  · 要继续扩，必须先【增加分区数】（且分区只能增不能减）")
print("=" * 76)
PYEOF
docker run --rm --network bench_kafka-net -v /tmp/l10_scale.py:/s.py \
  kafka-pybench:3.12 /app/.venv/bin/python /s.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -35
