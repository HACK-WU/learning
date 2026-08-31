#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 6 实测 1b：消费者确认（prefetch_count=1 下的确定性行为）

上一版 l6-ack.py 的结果被两个因素污染：
  1. prefetch 无上限 → broker 一次性把队列里所有消息推给消费者
  2. pika 的 consume 生成器会把消息缓冲在本地 → 代码只读了 1 条，其余已在本地缓冲区
  后果：auto_ack 实验里 3 条全丢（而非预期 1 条），requeue 实验里读到的是缓冲区里的下一条。
本版统一加 basic_qos(prefetch_count=1)，让行为确定可解释。
同时用 rabbitmqctl 读取 messages_ready / messages_unacknowledged 精确观察。
"""
import subprocess
import time
import pika

CRED = pika.PlainCredentials('learn', 'learn123')
PARAMS = pika.ConnectionParameters(host='localhost', port=5672, credentials=CRED)


def conn():
    return pika.BlockingConnection(PARAMS)


def stats(q):
    """用 rabbitmqctl 读 (ready, unacked, total)"""
    out = subprocess.run(
        ['docker', 'exec', 'rabbitmq-learn', 'rabbitmqctl', 'list_queues',
         'name', 'messages_ready', 'messages_unacknowledged', '-q'],
        capture_output=True, text=True).stdout
    for line in out.strip().splitlines():
        parts = line.split('\t')
        if len(parts) == 3 and parts[0] == q:
            return int(parts[1]), int(parts[2])
    return None, None


def show(q, tag):
    r, u = stats(q)
    print(f'    [{tag}] ready={r}  unacked={u}  total={r + u}')
    return r, u


def purge(q):
    c = conn()
    ch = c.channel()
    ch.queue_declare(queue=q, durable=True)
    ch.queue_purge(q)
    c.close()


def publish(q, n, prefix='m'):
    c = conn()
    ch = c.channel()
    ch.queue_declare(queue=q, durable=True)
    for i in range(1, n + 1):
        ch.basic_publish(exchange='', routing_key=q,
                         body=f'{prefix}-{i}'.encode(),
                         properties=pika.BasicProperties(delivery_mode=2))
    c.close()


print('=' * 72)
print('实验 1：auto_ack=True —— 消息在"投递瞬间"就算处理完了')
print('=' * 72)
Q1 = 'l6_ack_auto'
purge(Q1)
publish(Q1, 3)
show(Q1, '发送 3 条后')

c = conn()
ch = c.channel()
ch.queue_declare(queue=Q1, durable=True)
ch.basic_qos(prefetch_count=1)          # 关键：一次只给 1 条
m, p, b = next(ch.consume(queue=Q1, auto_ack=True, inactivity_timeout=5))
print(f'  收到: {b.decode()}  （auto_ack=True：broker 一投递就立即确认）')
show(Q1, '收到但未处理')
c.close()                                # 模拟处理到一半进程崩溃
time.sleep(1)
show(Q1, '崩溃后')
print('  → 队列从 3 条降到 2 条：那 1 条被"确认"了却没被处理，永久消失')

print()
print('=' * 72)
print('实验 2：manual ack —— 不 ack 就断开，消息回到队列')
print('=' * 72)
Q2 = 'l6_ack_manual'
purge(Q2)
publish(Q2, 3)
show(Q2, '发送 3 条后')

c = conn()
ch = c.channel()
ch.queue_declare(queue=Q2, durable=True)
ch.basic_qos(prefetch_count=1)
m, p, b = next(ch.consume(queue=Q2, auto_ack=False, inactivity_timeout=5))
print(f'  收到: {b.decode()}  delivery_tag={m.delivery_tag}  redelivered={m.redelivered}')
show(Q2, '收到但未 ack')
c.close()
time.sleep(1)
show(Q2, '崩溃后')
print('  → unacked 归零、ready 回到 3：消息从 unacked 状态被还回队列，没丢')

c = conn()
ch = c.channel()
ch.basic_qos(prefetch_count=1)
m, p, b = next(ch.consume(queue=Q2, auto_ack=False, inactivity_timeout=5))
print(f'  重新收到: {b.decode()}  redelivered={m.redelivered}  ← True = 这是重投')
ch.basic_ack(delivery_tag=m.delivery_tag)
time.sleep(0.5)
c.close()
show(Q2, 'ack 后')
print('  → total 从 3 降到 2：确认过的消息被真正删除')

print()
print('=' * 72)
print('实验 3：nack / reject —— 拒绝后"重新入队"与"直接丢弃"的分岔')
print('=' * 72)
Q3 = 'l6_ack_nack'
purge(Q3)
publish(Q3, 2)
show(Q3, '发送 2 条后')

c = conn()
ch = c.channel()
ch.queue_declare(queue=Q3, durable=True)
ch.basic_qos(prefetch_count=1)

m, p, b = next(ch.consume(queue=Q3, auto_ack=False, inactivity_timeout=5))
print(f'  [3a] 收到 {b.decode()}，执行 basic_nack(requeue=True)')
ch.basic_nack(delivery_tag=m.delivery_tag, requeue=True)
time.sleep(0.8)
show(Q3, 'nack requeue=True 后')
print('  → total 仍是 2：消息回到队列头部，可以再消费一次')

m, p, b = next(ch.consume(queue=Q3, auto_ack=False, inactivity_timeout=5))
print(f'       再次收到: {b.decode()}  redelivered={m.redelivered}  ← 同一条，重投标记为真')

print(f'  [3b] 对 {b.decode()} 执行 basic_reject(requeue=False)')
ch.basic_reject(delivery_tag=m.delivery_tag, requeue=False)
time.sleep(0.8)
show(Q3, 'reject requeue=False 后')
print('  → total 从 2 降到 1：这条被丢弃（若配了死信交换机则改投死信队列）')

# 把剩下那条也收掉，验证剩下的是 m-2
m, p, b = next(ch.consume(queue=Q3, auto_ack=False, inactivity_timeout=5))
print(f'       队列中剩下的是: {b.decode()}')
ch.basic_ack(delivery_tag=m.delivery_tag)
c.close()

print()
print('=' * 72)
print('实验 4：unacked 是什么样子 —— 消费慢于投递时的健康信号')
print('=' * 72)
Q4 = 'l6_ack_unacked'
purge(Q4)
publish(Q4, 5)
show(Q4, '发送 5 条后')

c = conn()
ch = c.channel()
ch.queue_declare(queue=Q4, durable=True)
ch.basic_qos(prefetch_count=2)          # 允许手上同时有 2 条未确认
print('  设置 prefetch_count=2，收 3 条但都不 ack：')
n = 0
for m, p, b in ch.consume(queue=Q4, auto_ack=False, inactivity_timeout=2):
    if m is None or n >= 3:
        break
    print(f'      收到 {b.decode()}')
    n += 1
show(Q4, f'收了 {n} 条未 ack')
print('  → ready 减少、unacked=2：unacked 就是"已投递但还没确认"的消息')
print('  → prefetch=2 意味着 broker 最多让 2 条处于 unacked，第 3 条根本不会推过来')
c.close()

print()
print('DONE')
