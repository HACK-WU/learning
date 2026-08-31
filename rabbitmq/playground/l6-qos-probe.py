#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 6 实测 2：两个关键边界行为

A) prefetch_count 对 auto_ack=True 的消费者是否生效？
   假设：不生效（AMQP 规范中 basic.qos 的 prefetch 只约束未确认消息数，
        而 auto_ack 模式下消息投递即确认，永远不会有"未确认"状态）
   上一版实验 1 已观察到：prefetch_count=1 + auto_ack=True → 3 条一次全推走。
   本实验用更大样本（10 条）确认，并与 manual ack 对照。

B) reject(requeue=False) 后的状态是否干净归零？
   上一版 3b 显示 unacked=1 残留，需确认是测量时序问题还是真实残留。
"""
import subprocess
import time
import pika

CRED = pika.PlainCredentials('learn', 'learn123')
PARAMS = pika.ConnectionParameters(host='localhost', port=5672, credentials=CRED)


def conn():
    return pika.BlockingConnection(PARAMS)


def stats(q):
    out = subprocess.run(
        ['docker', 'exec', 'rabbitmq-learn', 'rabbitmqctl', 'list_queues',
         'name', 'messages_ready', 'messages_unacknowledged', '-q'],
        capture_output=True, text=True).stdout
    for line in out.strip().splitlines():
        parts = line.split('\t')
        if len(parts) == 3 and parts[0] == q:
            return int(parts[1]), int(parts[2])
    return 0, 0


def show(q, tag):
    r, u = stats(q)
    print(f'    [{tag:28s}] ready={r:2d}  unacked={u:2d}  total={r + u:2d}')
    return r, u


def purge(q):
    c = conn(); ch = c.channel()
    ch.queue_declare(queue=q, durable=True); ch.queue_purge(q); c.close()


def publish(q, n):
    c = conn(); ch = c.channel()
    ch.queue_declare(queue=q, durable=True)
    for i in range(1, n + 1):
        ch.basic_publish(exchange='', routing_key=q, body=f'm-{i}'.encode(),
                         properties=pika.BasicProperties(delivery_mode=2))
    c.close()


print('=' * 72)
print('实验 A：prefetch_count 对 auto_ack=True 是否生效？')
print('=' * 72)

# A-1: auto_ack=True + prefetch=1
QA = 'l6_qos_autoack'
purge(QA)
publish(QA, 10)
show(QA, '发送 10 条')

c = conn(); ch = c.channel()
ch.queue_declare(queue=QA, durable=True)
ch.basic_qos(prefetch_count=1)
m, p, b = next(ch.consume(queue=QA, auto_ack=True, inactivity_timeout=3))
print(f'  auto_ack=True + prefetch_count=1，只读 1 条（{b.decode()}）:')
show(QA, '收到 1 条后')
c.close()
print('  → 若 prefetch 生效，应只剩 9 条；实际如上。')

# A-2: auto_ack=False + prefetch=1
QB = 'l6_qos_manual'
purge(QB)
publish(QB, 10)
show(QB, '发送 10 条')

c = conn(); ch = c.channel()
ch.queue_declare(queue=QB, durable=True)
ch.basic_qos(prefetch_count=1)
m, p, b = next(ch.consume(queue=QB, auto_ack=False, inactivity_timeout=3))
print(f'  auto_ack=False + prefetch_count=1，只读 1 条（{b.decode()}，不 ack）:')
show(QB, '收到 1 条后')
ch.basic_ack(delivery_tag=m.delivery_tag)
c.close()
time.sleep(0.5)

# A-3: auto_ack=False + 不设 prefetch（对照组，沿用课 4 已有发现）
QC = 'l6_qos_noprefetch'
purge(QC)
publish(QC, 10)
show(QC, '发送 10 条')
c = conn(); ch = c.channel()
ch.queue_declare(queue=QC, durable=True)
m, p, b = next(ch.consume(queue=QC, auto_ack=False, inactivity_timeout=3))
print(f'  auto_ack=False + 不设 prefetch，只读 1 条（{b.decode()}，不 ack）:')
show(QC, '收到 1 条后')
c.close()
time.sleep(0.5)

print()
print('=' * 72)
print('实验 B：reject(requeue=False) 后状态是否干净？')
print('=' * 72)
QD = 'l6_reject_clean'
purge(QD)
publish(QD, 3)
show(QD, '发送 3 条')

c = conn(); ch = c.channel()
ch.queue_declare(queue=QD, durable=True)
ch.basic_qos(prefetch_count=1)
m, p, b = next(ch.consume(queue=QD, auto_ack=False, inactivity_timeout=3))
print(f'  收到 {b.decode()}，执行 basic_reject(requeue=False)')
ch.basic_reject(delivery_tag=m.delivery_tag, requeue=False)
for wait in (0.5, 1.5, 3.0):
    time.sleep(wait)
    show(QD, f'reject 后 +{wait}s')
c.close()
time.sleep(1)
show(QD, '关闭连接后')
print('  → total 应从 3 降到 2，且 unacked 归零')

print()
print('DONE')
