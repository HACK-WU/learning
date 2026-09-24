#!/bin/bash
# 课 10 实验②：并发消费 + 位移提交乱序坑（真 Kafka）
#
# 核心问题：多线程处理时，offset 大的先处理完先提交，
#           若此时崩溃 -> offset 小的其实没处理 -> 消息永久丢失
# 这是消费端并发最经典的事故，必须真跑出来
set -u
cat > /tmp/l10_offset.py <<'PYEOF'
import json, time, threading
from confluent_kafka import Consumer, Producer, TopicPartition, KafkaException

BOOT = "kafka-1:9092,kafka-2:9092,kafka-3:9092"
TOPIC = "l10-offset-demo"
GROUP = "l10-offset-g"

def make_topic():
    from confluent_kafka.admin import AdminClient, NewTopic
    a = AdminClient({"bootstrap.servers": BOOT})
    try:
        a.create_topics([NewTopic(TOPIC, num_partitions=1, replication_factor=1)])
        time.sleep(2)
    except Exception as e:
        print(f"  (topic 已存在或创建失败: {str(e)[:50]})")

def produce(n):
    p = Producer({"bootstrap.servers": BOOT})
    for i in range(n):
        p.produce(TOPIC, json.dumps({"i": i, "slow": (i % 5 == 0)}).encode(),
                  key=str(i).encode())
    p.flush()

print("=" * 74)
print("课 10 · 并发消费的位移提交乱序坑（真 Kafka）")
print("=" * 74)

make_topic()
N = 20
produce(N)
print(f"\n[1] 生产 {N} 条到 {TOPIC}（1 分区），其中 i%5==0 的是『慢消息』")

# ---------- 错误示范：并发处理 + 各自提交 ----------
print(f"\n[2] 错误示范：4 线程并发处理，谁先处理完谁提交 offset")
print(f"    {'处理线程':<10}{'offset':<10}{'耗时':<10}{'提交offset':<12}")
print(f"    {'-'*44}")

consumed = []
lock = threading.Lock()
c = Consumer({
    "bootstrap.servers": BOOT,
    "group.id": GROUP,
    "auto.offset.reset": "earliest",
    "enable.auto.commit": False,     # 手动提交，模拟"处理完再提交"
})
c.subscribe([TOPIC])

def handle(msg, wid):
    d = json.loads(msg.value())
    time.sleep(0.6 if d["slow"] else 0.05)     # 慢消息 12 倍耗时
    with lock:
        # 处理完立刻提交：先完成的先提交
        c.commit(message=msg, asynchronous=False)
        consumed.append(msg.offset())
        print(f"    wid={wid:<6}{msg.offset():<10}"
              f"{'0.6s' if d['slow'] else '0.05s':<10}{msg.offset()+1:<12}")

msgs = []
t0 = time.perf_counter()
while len(msgs) < N and time.perf_counter()-t0 < 40:
    m = c.poll(1.0)
    if m is None: continue
    if m.error():
        print(f"    error: {m.error()}"); continue
    msgs.append(m)

# 并发处理：慢的(offset小)后完成，快的(offset大)先完成
threads = []
for i, m in enumerate(msgs):
    t = threading.Thread(target=handle, args=(m, i % 4))
    threads.append(t); t.start()
for t in threads: t.join()

print(f"\n[3] 结果分析:")
print(f"    处理顺序（完成顺序）: {consumed[:10]} ...")
print(f"    -> 大 offset 先完成并提交，小 offset 还在处理中")
print(f"    -> 此刻若进程崩溃，已提交 offset 之前的小 offset【永远不会被再消费】")

# 验证：重新加入组，看 committed 是多少、还剩多少没消费
committed = c.committed([TopicPartition(TOPIC, 0)])
print(f"\n[4] 崩漬模拟：查 committed offset（这是【最终态】，非风险窗口）")
for tp in committed:
    print(f"    {tp.topic}[{tp.partition}] committed = {tp.offset}")

# 用新 group 从头消费，确认数据其实还在（说明丢的是"处理"不是"数据")
c2 = Consumer({"bootstrap.servers": BOOT, "group.id": GROUP+"-check",
               "auto.offset.reset": "earliest", "enable.auto.commit": False})
c2.subscribe([TOPIC])
real = 0
t0=time.perf_counter()
while real < N and time.perf_counter()-t0 < 20:
    m = c2.poll(1.0)
    if m and not m.error(): real += 1
c2.close()
print(f"    新 group 从头消费可得: {real} 条")
print(f"    -> 数据没丢；本例四条慢消息最终也处理完了")
print(f"    ⚠ 但看【过程】：offset 1 完成时已提交 2，而 offset 0 还在处理")
print(f"      那一刻崩溃 -> offset 0 被永久跳过。风险窗口在过程中，不在终态")

c.close()

print("\n" + "=" * 74)
print("结论")
print("=" * 74)
print("  · 并发处理 + 『谁完成谁提交』= 消息丢失（提交越过了未处理消息）")
print("  · 根因：offset 是【分区内有序】的，但并发处理让它【完成无序】")
print("  · 正解一：按 offset 顺序提交（维护连续水位线）")
print("  · 正解二：处理与提交分离，只提交『已连续完成』的最大 offset+1")
print("  · 正解三：业务侧幂等（最根本，也是课 6/8 的结论呼应）")
print("=" * 74)
PYEOF
docker run --rm --network bench_kafka-net -v /tmp/l10_offset.py:/o.py \
  kafka-pybench:3.12 /app/.venv/bin/python /o.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -50
