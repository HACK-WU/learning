#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8 知识点 3：顺序性
======================
目标：实测证明多消费者为什么破坏顺序，以及保序的代价。

核心命题：
  RabbitMQ 只保证「单个消费者 + 单信道」下按 FIFO 顺序投递，
  一旦并发消费，全局顺序必然被打乱。

待验证：
  Q1: 单消费者 → 顺序是否严格保持？（对照基准）
  Q2: 多消费者（并发）→ 顺序如何被打乱？
  Q3: 单消费者但"处理中失败并重投" → 顺序是否也会破？（最易忽略！）
  Q4: prefetch=1 + 单消费者，能否既保序又吞吐？（权衡）

关键洞察（教学要点）：
  顺序被破坏有两个独立来源：
    ① 并发：多个消费者同时处理，快慢不同 → 完成顺序 ≠ 投递顺序
    ② 重投：一条消息失败重投后，可能排到后面 → 即使单消费者也会乱序
  ⚠️ ② 常被忽略：很多人以为"只开一个消费者就万事大吉"，其实不然。

实测环境：RabbitMQ 4.3.5 / pika 1.4.4
"""
import time
import threading
import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')
N = 12


def conn():
    return pika.BlockingConnection(
        pika.ConnectionParameters(host=HOST, port=PORT, credentials=CRED,
                                  heartbeat=600, blocked_connection_timeout=300))


def reset(*qs):
    c = conn()
    ch = c.channel()
    for q in qs:
        try:
            ch.queue_delete(queue=q)
        except Exception:
            pass
    c.close()


def setup(*qs):
    c = conn()
    ch = c.channel()
    for q in qs:
        ch.queue_declare(queue=q, durable=True)
    c.close()


def publish(q, n):
    c = conn()
    ch = c.channel()
    ch.confirm_delivery()
    for i in range(1, n + 1):
        ch.basic_publish(exchange='', routing_key=q, body=f'msg-{i:02d}'.encode(),
                         properties=pika.BasicProperties(delivery_mode=2))
    c.close()


def depth(q):
    c = conn()
    ch = c.channel()
    try:
        n = ch.queue_declare(queue=q, durable=True, passive=True).method.message_count
    except Exception:
        n = -1
    c.close()
    return n


def is_sorted(seq):
    """判断是否严格递增（按消息编号）"""
    nums = []
    for s in seq:
        try:
            nums.append(int(s.split('-')[1]))
        except Exception:
            return False
    return nums == sorted(nums), nums


print("=" * 74)
print("知识点 3：顺序性 —— 实测")
print("=" * 74)

# =====================================================================
# Q1：单消费者 → 顺序保持（基准）
# =====================================================================
print("\n" + "-" * 74)
print("【Q1】单消费者：顺序应保持（基准）")
print("-" * 74)

Q1 = 'l8.ord.single'
reset(Q1)
setup(Q1)
publish(Q1, N)

order_q1 = []
done = threading.Event()


def on_q1(ch, method, properties, body):
    order_q1.append(body.decode())
    ch.basic_ack(delivery_tag=method.delivery_tag)


c = conn()
ch = c.channel()
ch.basic_qos(prefetch_count=1)
ch.basic_consume(queue=Q1, on_message_callback=on_q1, auto_ack=False)
deadline = time.time() + 10
while len(order_q1) < N and time.time() < deadline:
    c.process_data_events(time_limit=0.3)
c.close()

ok1, nums1 = is_sorted(order_q1)
print(f"    投递顺序: msg-01 ... msg-{N:02d}")
print(f"    处理顺序: {' '.join(order_q1)}")
print(f"    >>> 顺序保持: {ok1}")

# =====================================================================
# Q2：多消费者并发 → 顺序被打乱
# =====================================================================
print("\n" + "-" * 74)
print("【Q2】多消费者（3 个并发）：顺序必然打乱")
print("-" * 74)

Q2 = 'l8.ord.multi'
reset(Q2)
setup(Q2)
publish(Q2, N)

order_q2 = []
lock = threading.Lock()


def worker(wid, sleep_time):
    """不同消费者处理速度不同：wid=0 快，wid=2 慢"""
    c = conn()
    ch = c.channel()
    ch.basic_qos(prefetch_count=1)

    def cb(ch, method, properties, body):
        time.sleep(sleep_time)          # 模拟处理耗时差异
        with lock:
            order_q2.append(f"{body.decode()}(C{wid})")
        ch.basic_ack(delivery_tag=method.delivery_tag)

    ch.basic_consume(queue=Q2, on_message_callback=cb, auto_ack=False)
    deadline = time.time() + 12
    while time.time() < deadline:
        c.process_data_events(time_limit=0.3)
        with lock:
            if len(order_q2) >= N:
                break
    try:
        c.close()
    except Exception:
        pass


threads = [threading.Thread(target=worker, args=(i, 0.01 * (i + 1))) for i in range(3)]
for t in threads:
    t.start()
for t in threads:
    t.join(timeout=15)

ok2, nums2 = is_sorted([s.split('(')[0] for s in order_q2])
print(f"    C0(快) C1(中) C2(慢) 三个消费者并发")
print(f"    完成顺序: {' '.join(order_q2)}")
print(f"    >>> 顺序保持: {ok2}")
if not ok2:
    print(f"    ★ 顺序被打乱：消息编号序列 {nums2}")
    print(f"      原因：快的消费者先完成，与投递顺序无关")

# =====================================================================
# Q3：单消费者 + 重投 → 顺序也会破（最易忽略）
# =====================================================================
print("\n" + "-" * 74)
print("【Q3】单消费者 + 消息重投：顺序同样会被打破 ★易忽略")
print("-" * 74)

Q3 = 'l8.ord.redeliver'
reset(Q3)
setup(Q3)
# 只发 5 条，让 msg-03 在第一次处理时 nack 重投
publish(Q3, 5)

order_q3 = []
attempt_count = {}


def on_q3(ch, method, properties, body):
    name = body.decode()
    attempt_count[name] = attempt_count.get(name, 0) + 1
    n = attempt_count[name]
    if name == 'msg-03' and n == 1:
        print(f"    {name} 第 1 次处理失败 → nack(requeue=True)，重新排队")
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
        return
    order_q3.append(name)
    print(f"    {name} 处理完成")
    ch.basic_ack(delivery_tag=method.delivery_tag)


c = conn()
ch = c.channel()
ch.basic_qos(prefetch_count=1)
ch.basic_consume(queue=Q3, on_message_callback=on_q3, auto_ack=False)
deadline = time.time() + 12
while len(order_q3) < 5 and time.time() < deadline:
    c.process_data_events(time_limit=0.3)
c.close()

ok3, nums3 = is_sorted(order_q3)
print(f"\n    最终完成顺序: {' '.join(order_q3)}")
print(f"    >>> 顺序保持: {ok3}")
if not ok3:
    print(f"    ★ 即使只有 1 个消费者，重投也让 msg-03 排到了队尾！")
    print(f"      顺序破坏来源②：失败重投 —— 与并发无关，单消费者同样中招")

# =====================================================================
# Q4：单消费者 prefetch 权衡（吞吐代价）
# =====================================================================
print("\n" + "-" * 74)
print("【Q4】保序的代价：单消费者 prefetch 吞吐对比")
print("-" * 74)

M = 300


def throughput(qname, prefetch, consumers):
    reset(qname)
    setup(qname)
    publish(qname, M)
    counter = {'n': 0}
    lock_t = threading.Lock()
    stop = threading.Event()

    def w():
        c = conn()
        ch = c.channel()
        if prefetch:
            ch.basic_qos(prefetch_count=prefetch)

        def cb(ch, method, properties, body):
            ch.basic_ack(delivery_tag=method.delivery_tag)
            with lock_t:
                counter['n'] += 1
                if counter['n'] >= M:
                    stop.set()

        ch.basic_consume(queue=qname, on_message_callback=cb, auto_ack=False)
        deadline = time.time() + 30
        while not stop.is_set() and time.time() < deadline:
            c.process_data_events(time_limit=0.2)
        try:
            c.close()
        except Exception:
            pass

    ts = [threading.Thread(target=w) for _ in range(consumers)]
    t0 = time.time()
    for t in ts:
        t.start()
    for t in ts:
        t.join(timeout=35)
    dt = time.time() - t0
    return counter['n'] / dt if dt > 0 else 0


r_single_1 = throughput('l8.ord.tp.a', 1, 1)
r_single_50 = throughput('l8.ord.tp.b', 50, 1)
r_multi_50 = throughput('l8.ord.tp.c', 50, 4)

print(f"\n    {M} 条消息吞吐对比：")
print(f"      单消费者 prefetch=1      : {r_single_1:8.1f} 条/秒  （严格保序）")
print(f"      单消费者 prefetch=50     : {r_single_50:8.1f} 条/秒  （保序，略快）")
print(f"      4 消费者  prefetch=50    : {r_multi_50:8.1f} 条/秒  （不保序，最快）")
if r_single_1 > 0:
    print(f"\n    >>> 严格保序（单消费者 p=1）的吞吐约为 4 并发的 "
          f"{r_single_1 / r_multi_50 * 100:.1f}%")

print("\n" + "=" * 74)
print("知识点 3 实测小结")
print("=" * 74)
print(f"  Q1 单消费者        : 顺序保持 = {ok1}")
print(f"  Q2 多消费者并发    : 顺序保持 = {ok2}  ← 并发破坏顺序")
print(f"  Q3 单消费者+重投   : 顺序保持 = {ok3}  ← 重投同样破坏顺序 ★易忽略")
print(f"  Q4 保序代价        : 单p=1 {r_single_1:.0f} / 单p=50 {r_single_50:.0f} / 4并发 {r_multi_50:.0f} 条/秒")
print()
print("  核心结论：")
print("   1. RabbitMQ 只保证 FIFO 投递顺序，不保证『处理完成』顺序")
print("   2. 顺序两大杀手：并发消费 + 失败重投（后者常被忽略）")
print("   3. 严格保序 = 单消费者 + prefetch=1，代价是吞吐大幅下降")
print("   4. 更实用的做法：不追求全局顺序，只保证『同一业务键有序』")
print("      （按 order_id 哈希分队列/分区，同键串行、不同键并行）")
