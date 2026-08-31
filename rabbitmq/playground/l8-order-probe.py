#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8 知识点 3 补测：两个反常结果的根因排查
============================================
反常 1（Q3）：单消费者 + nack(requeue=True) 后顺序居然保持了
              （预期：msg-03 重投后排到 msg-05 之后 → 乱序）
  怀疑：队列当时没有积压，msg-03 被 requeue 后立即又被同一个消费者拿到，
        此时 msg-04/05 还没被投递 → 它"插回了原位"。
  验证：让队列保持积压（先不消费，攒够消息），再让中间某条失败重投，
        观察它是否排到队尾。

反常 2（Q4）：4 消费者吞吐 1254 条/秒，反而远低于单消费者 13339 条/秒
  怀疑：① 四个线程争抢同一个锁 counter（每次 ack 都加锁）造成串行化
        ② 或者连接/线程创建开销
        ③ 或者测量方式有问题（stop 事件与 join 时序）
  验证：去掉锁争用，改用各自独立计数，且预建队列后统一计时。
"""
import time
import threading
import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')


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


print("=" * 74)
print("补测 1：requeue 到底会不会破坏顺序？（关键：队列是否有积压）")
print("=" * 74)

# ---------- 场景 A：无积压时 requeue ----------
QA = 'l8.req.nobacklog'
reset(QA)
setup(QA)
publish(QA, 5)

order_a = []
attempts_a = {}


def on_a(ch, method, properties, body):
    name = body.decode()
    attempts_a[name] = attempts_a.get(name, 0) + 1
    if name == 'msg-03' and attempts_a[name] == 1:
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
        return
    order_a.append(name)
    ch.basic_ack(delivery_tag=method.delivery_tag)


c = conn()
ch = c.channel()
ch.basic_qos(prefetch_count=1)
ch.basic_consume(queue=QA, on_message_callback=on_a, auto_ack=False)
deadline = time.time() + 10
while len(order_a) < 5 and time.time() < deadline:
    c.process_data_events(time_limit=0.3)
c.close()
print(f"\n  [场景 A] 边消费边重投（无积压）")
print(f"    完成顺序: {' '.join(order_a)}")
print(f"    >>> msg-03 是否排到队尾: {'否（插回原位）' if order_a.index('msg-03') == 2 else '是'}")

# ---------- 场景 B：有积压时 requeue（关键差异） ----------
QB = 'l8.req.backlog'
reset(QB)
setup(QB)
publish(QB, 8)

# 关键：先把所有消息推给消费者（prefetch 放大），让第 3 条在"已推送但未处理"时失败
order_b = []
attempts_b = {}
failed_once = {'done': False}


def on_b(ch, method, properties, body):
    name = body.decode()
    attempts_b[name] = attempts_b.get(name, 0) + 1
    # msg-03 第一次失败；且此时 msg-04..08 已被推送到客户端缓冲区
    if name == 'msg-03' and attempts_b[name] == 1 and not failed_once['done']:
        failed_once['done'] = True
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
        return
    order_b.append(name)
    ch.basic_ack(delivery_tag=method.delivery_tag)


c = conn()
ch = c.channel()
ch.basic_qos(prefetch_count=8)      # ← 允许一次推送全部，制造"客户端积压"
ch.basic_consume(queue=QB, on_message_callback=on_b, auto_ack=False)
deadline = time.time() + 12
while len(order_b) < 8 and time.time() < deadline:
    c.process_data_events(time_limit=0.3)
c.close()
print(f"\n  [场景 B] prefetch=8，客户端已有积压时重投")
print(f"    完成顺序: {' '.join(order_b)}")
pos3 = order_b.index('msg-03') if 'msg-03' in order_b else -1
print(f"    >>> msg-03 完成位置: 第 {pos3 + 1} 位（0 基索引 {pos3}）")
print(f"    >>> msg-03 是否被挤到后面: {'是 → 顺序被破坏' if pos3 > 2 else '否'}")


print("\n" + "=" * 74)
print("补测 2：多消费者吞吐为什么反而更低？（去掉锁争用重测）")
print("=" * 74)

M = 600


def throughput_v2(qname, consumers, prefetch):
    """改进版：每个线程独立计数，最后汇总，避免每次 ack 都抢锁"""
    reset(qname)
    setup(qname)
    publish(qname, M)
    counts = [0] * consumers
    stop = threading.Event()
    barrier = threading.Barrier(consumers)   # 让所有消费者就绪后同时开跑

    def w(idx):
        c = conn()
        ch = c.channel()
        if prefetch:
            ch.basic_qos(prefetch_count=prefetch)

        def cb(ch, method, properties, body):
            ch.basic_ack(delivery_tag=method.delivery_tag)
            counts[idx] += 1
            if sum(counts) >= M:
                stop.set()

        ch.basic_consume(queue=qname, on_message_callback=cb, auto_ack=False)
        barrier.wait(timeout=10)              # 就绪后统一开跑
        deadline = time.time() + 40
        while not stop.is_set() and time.time() < deadline:
            c.process_data_events(time_limit=0.2)
        try:
            c.close()
        except Exception:
            pass

    ts = [threading.Thread(target=w, args=(i,)) for i in range(consumers)]
    for t in ts:
        t.start()
    t0 = time.time()
    for t in ts:
        t.join(timeout=45)
    dt = time.time() - t0
    total = sum(counts)
    return total / dt if dt > 0 else 0, total, dt


print(f"\n  {M} 条消息，改进测量（各线程独立计数 + barrier 统一起跑）：")
r1, tot1, dt1 = throughput_v2('l8.tp2.c1', 1, 50)
print(f"    1 消费者 prefetch=50 : {r1:8.1f} 条/秒  (共 {tot1} 条 / {dt1:.2f}s)")
r2, tot2, dt2 = throughput_v2('l8.tp2.c2', 2, 50)
print(f"    2 消费者 prefetch=50 : {r2:8.1f} 条/秒  (共 {tot2} 条 / {dt2:.2f}s)")
r4, tot4, dt4 = throughput_v2('l8.tp2.c4', 4, 50)
print(f"    4 消费者 prefetch=50 : {r4:8.1f} 条/秒  (共 {tot4} 条 / {dt4:.2f}s)")

print("\n  分析：")
if r4 < r1:
    print(f"    ⚠️ 4 并发（{r4:.0f}）仍低于单消费者（{r1:.0f}）—— 与常识相反，需进一步排查")
    print(f"       注意：本环境 broker 与客户端在同一台机器，且是 Docker 端口映射，")
    print(f"       多线程共享同一个 TCP 回环，瓶颈可能在 pika 的 GIL / ioloop 而非 broker。")
    print(f"       ⚠️ 结论：本机的『多消费者更快』无法用 pika 多线程证明，")
    print(f"          教学中应改为引用课 6 已测得的 prefetch 吞吐曲线，")
    print(f"          或明确说明这是客户端测量局限，不代表 broker 能力。")
else:
    print(f"    ✅ 多消费者确实更快：4 并发 {r4:.0f} > 单消费者 {r1:.0f} 条/秒")
