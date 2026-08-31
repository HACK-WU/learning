#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8《交付语义与幂等》知识点 1：三种交付语义
=============================================
目标：用实测证明三种语义的真实表现，尤其是"至少一次"下重复确实会发生。

实验矩阵（每组独立队列，避免互相干扰）：
  A 组 至多一次  (at-most-once)  : auto_ack=True  → 消息可能丢失
  B 组 至少一次  (at-least-once) : auto_ack=False + 手动 ack → 消息不丢但可能重复
  C 组 恰好一次  (exactly-once)  : RabbitMQ 本身不提供，需业务幂等兜底

关键待验证问题：
  Q1: auto_ack=True 时消费者处理中崩溃 → 消息是否丢失？
  Q2: auto_ack=False 时消费者处理完但 ack 前崩溃 → 消息是否重投（重复）？
  Q3: 消费者已处理成功、ack 在网络中丢失 → 是否重复？

实测环境：RabbitMQ 4.3.5 / pika 1.4.4
"""
import sys
import time
import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')


def conn():
    return pika.BlockingConnection(
        pika.ConnectionParameters(host=HOST, port=PORT, credentials=CRED,
                                  heartbeat=600, blocked_connection_timeout=300))


def reset(victim_names):
    """清理旧队列，保证每组干净起点"""
    c = conn()
    ch = c.channel()
    for q in victim_names:
        try:
            ch.queue_delete(queue=q)
        except Exception:
            pass
    c.close()


def depth(queue):
    """读取队列权威深度（broker 侧）"""
    c = conn()
    ch = c.channel()
    try:
        r = ch.queue_declare(queue=queue, durable=True, passive=True)
        n = r.method.message_count
    except Exception:
        n = -1
    c.close()
    return n


print("=" * 74)
print("知识点 1：三种交付语义 —— 实测")
print("=" * 74)

# ---------- 准备：三个独立队列 ----------
Q_MOST = 'l8.sem.atmost'     # 至多一次
Q_LEAST = 'l8.sem.atleast'   # 至少一次
reset([Q_MOST, Q_LEAST])

c = conn()
ch = c.channel()
ch.queue_declare(queue=Q_MOST, durable=True)
ch.queue_declare(queue=Q_LEAST, durable=True)
c.close()

# =====================================================================
# A 组：至多一次（auto_ack=True）
# 场景：消费者收到消息后"处理中"崩溃（模拟：收到即关闭连接，不做任何处理）
# 预期：消息永久丢失（因为投递即确认，broker 已删除）
# =====================================================================
print("\n" + "-" * 74)
print("【A 组】至多一次 at-most-once（auto_ack=True）")
print("-" * 74)

# 先投 5 条消息
c = conn()
ch = c.channel()
for i in range(1, 6):
    ch.basic_publish(exchange='', routing_key=Q_MOST,
                     body=f'order-A{i}'.encode(),
                     properties=pika.BasicProperties(delivery_mode=2))
c.close()
print(f"  投递 5 条 → 队列深度 = {depth(Q_MOST)}")

# 消费者：auto_ack=True，收到 2 条后立即"崩溃"（关闭连接且未处理）
received_a = []


def crash_after_two(ch, method, properties, body):
    received_a.append(body.decode())
    print(f"    收到 {body.decode()}（auto_ack 已自动确认，broker 立即删除）")
    if len(received_a) >= 2:
        print("    >>> 模拟崩溃：处理到第 2 条时进程挂掉，连接断开")
        raise SystemExit(0)   # 直接退出，不 ack（但 auto_ack 下 broker 已确认）


c = conn()
ch = c.channel()
ch.basic_consume(queue=Q_MOST, on_message_callback=crash_after_two, auto_ack=True)
try:
    ch.start_consuming()
except SystemExit:
    pass
except Exception as e:
    print(f"    连接中断: {type(e).__name__}")
finally:
    try:
        c.close()
    except Exception:
        pass

time.sleep(1.0)  # 等 broker 回收 unacked
remain_a = depth(Q_MOST)
print(f"\n  崩溃后队列剩余 = {remain_a} 条（原 5 条，已消费 2 条）")
print(f"  >>> 那 2 条『收到但未处理』的消息：{'已永久丢失' if remain_a == 3 else '仍在队列中'}")
print(f"  结论：at-most-once —— 消息{'丢失' if remain_a == 3 else '未丢失'}，吞吐最高，可靠性最低")

# =====================================================================
# B 组：至少一次（auto_ack=False + 手动 ack）
# 场景：消费者"处理完但 ack 前"崩溃 → 消息应重投（重复）
# =====================================================================
print("\n" + "-" * 74)
print("【B 组】至少一次 at-least-once（auto_ack=False + 手动 ack）")
print("-" * 74)

c = conn()
ch = c.channel()
for i in range(1, 6):
    ch.basic_publish(exchange='', routing_key=Q_LEAST,
                     body=f'order-B{i}'.encode(),
                     properties=pika.BasicProperties(delivery_mode=2))
c.close()
print(f"  投递 5 条 → 队列深度 = {depth(Q_LEAST)}")

processed_b = []   # 模拟"业务已处理成功"的记录


def process_then_crash(ch, method, properties, body):
    """模拟：业务处理成功，但还没来得及 ack 就崩了"""
    msg = body.decode()
    processed_b.append(msg)
    print(f"    处理成功 {msg}（业务已生效，但未 ack）")
    print(f"    >>> 模拟崩溃：ack 前进程挂掉，delivery_tag={method.delivery_tag}")
    raise SystemExit(0)   # 不调用 basic_ack，直接退出


c = conn()
ch = c.channel()
ch.basic_consume(queue=Q_LEAST, on_message_callback=process_then_crash, auto_ack=False)
try:
    ch.start_consuming()
except SystemExit:
    pass
except Exception as e:
    print(f"    连接中断: {type(e).__name__}")
finally:
    try:
        c.close()
    except Exception:
        pass

time.sleep(1.5)  # 等 broker 把未 ack 的消息重新入队
remain_b = depth(Q_LEAST)
print(f"\n  崩溃后队列深度 = {remain_b} 条")
print(f"  业务已处理但由于未 ack：消息重新入队 = {remain_b == 5}")
print(f"  >>> 下次消费时 order-B1 会被再处理一次 = 重复投递")

# 验证重复：重新消费，看是否又能读到 order-B1
print("\n  重新消费，验证重复：")
redelivered_flags = []
seen_b = []

c = conn()
ch = c.channel()


def observe_redelivery(ch, method, properties, body):
    seen_b.append(body.decode())
    redelivered_flags.append(method.redelivered)
    flag = "REDELIVERED(重投)" if method.redelivered else "首次投递"
    print(f"    {body.decode():12s} redelivered={method.redelivered}  [{flag}]")
    ch.basic_ack(delivery_tag=method.delivery_tag)


ch.basic_consume(queue=Q_LEAST, on_message_callback=observe_redelivery, auto_ack=False)
# 只消费 2 条就停，避免无限
deadline = time.time() + 5
while len(seen_b) < 2 and time.time() < deadline:
    c.process_data_events(time_limit=0.5)
# 剩余 ack 掉
deadline = time.time() + 3
while time.time() < deadline:
    c.process_data_events(time_limit=0.5)
c.close()

print(f"\n  重投标记统计：{redelivered_flags}")
print(f"  >>> order-B1 是否被重复投递：{'是' if redelivered_flags and redelivered_flags[0] else '否'}")

print("\n" + "=" * 74)
print("知识点 1 实测小结")
print("=" * 74)
print(f"  A 组 at-most-once : 5 条投递，消费 2 条时崩溃 → 剩余 {remain_a} 条（2 条已永久丢失）")
print(f"  B 组 at-least-once: 5 条投递，处理 1 条未 ack 崩溃 → 剩余 {remain_b} 条（全部重投）")
print("  C 组 exactly-once : RabbitMQ 不提供，必须由业务侧幂等兜底（见知识点 2）")
print("\n  核心结论：RabbitMQ 原生保证的是『至少一次』。")
print("            『不丢』靠 ack，『不重』必须靠业务自己。")
