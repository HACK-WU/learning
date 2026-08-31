#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""验证 P0：nack(requeue=True) 会不会写入/累加 x-death 头？

讲义第四幕的 retry_count() 依赖 x-death 计数。
官方说明：x-death 只在消息被**死信化**时写入 —— 即
  ① reject/nack 且 requeue=False（且配了 DLX）
  ② 消息 TTL 过期
  ③ 队列超过 max-length
而 nack(requeue=True) 是"重新入队"，消息从未离开原队列，
因此**不会**产生 x-death。

若本实验证实 requeue=True 不写 x-death，则讲义里
"用 x-death 计数 + requeue=True 重试"是错的：计数永远是 0，
会无限重试 —— 正是讲义自己警告的死循环。
"""
import pika

CRED = pika.PlainCredentials('learn', 'learn123')
PARAMS = pika.ConnectionParameters(host='localhost', port=5672, credentials=CRED)

Q = 'l6_xdeath_probe'
DLX = 'l6.xdeath.dlx'
DLQ = 'l6_xdeath_dlq'


def conn():
    return pika.BlockingConnection(PARAMS)


c = conn()
ch = c.channel()

# 兜底交换机与队列
ch.exchange_declare(exchange=DLX, exchange_type='fanout', durable=True)
ch.queue_declare(queue=DLQ, durable=True)
ch.queue_bind(exchange=DLX, queue=DLQ)

# 主队列，配 DLX
ch.queue_declare(queue=Q, durable=True,
                 arguments={'x-dead-letter-exchange': DLX})
ch.queue_purge(Q)
ch.queue_purge(DLQ)

ch.basic_publish(exchange='', routing_key=Q, body=b'probe-msg',
                 properties=pika.BasicProperties(delivery_mode=2))

print('=' * 70)
print('实验：连续 nack(requeue=True) 三次，观察 properties.headers')
print('=' * 70)

for i in range(1, 4):
    m, props, body = next(ch.consume(queue=Q, auto_ack=False, inactivity_timeout=3))
    if m is None:
        print(f'  第 {i} 次：没收到消息')
        break
    headers = props.headers or {}
    xd = headers.get('x-death')
    print(f'  第 {i} 次收到 {body.decode()}:')
    print(f'      redelivered = {m.redelivered}')
    print(f'      headers     = {headers}')
    print(f'      x-death     = {xd}')
    ch.basic_nack(delivery_tag=m.delivery_tag, requeue=True)

print()
print('=' * 70)
print('结论判定')
print('=' * 70)

# 再来一次，这次用 requeue=False 送死信，看 x-death 是否出现
m, props, body = next(ch.consume(queue=Q, auto_ack=False, inactivity_timeout=3))
if m:
    print(f'  用 requeue=False 拒绝 {body.decode()} → 应进入死信队列')
    ch.basic_nack(delivery_tag=m.delivery_tag, requeue=False)

# 从死信队列读，看 x-death
c2 = conn()
ch2 = c2.channel()
m2, p2, b2 = next(ch2.consume(queue=DLQ, auto_ack=False, inactivity_timeout=3))
if m2:
    print(f'  死信队列收到 {b2.decode()}:')
    print(f'      headers = {p2.headers or {}}')
    xd2 = (p2.headers or {}).get('x-death')
    print(f'      x-death = {xd2}')
    if xd2:
        print(f'      → requeue=False 后 x-death 才出现，count={xd2[0].get("count")}')
    ch2.basic_ack(delivery_tag=m2.delivery_tag)
c2.close()
c.close()

print()
print('DONE')
