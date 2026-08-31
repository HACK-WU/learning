#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""课5 持久化验证：重启后从宿主机读取，确认消息内容"""
import pika

CR = pika.PlainCredentials('learn', 'learn123')
CP = pika.ConnectionParameters(host='localhost', port=5672, credentials=CR)
c = pika.BlockingConnection(CP)
ch = c.channel()

print("=== 重启后队列消息数（宿主机视角）===")
for q in ['l5_durable_survive', 'l5_transient_survive']:
    try:
        r = ch.queue_declare(queue=q, durable=True, passive=True)
        print(f"[{q}] 消息数 = {r.method.message_count}")
    except Exception as e:
        print(f"[{q}] 异常: {type(e).__name__}")

print("\n=== 取出 l5_durable_survive 的内容 ===")
n = 0
while True:
    m, h, b = ch.basic_get(queue='l5_durable_survive', auto_ack=True)
    if not m:
        break
    n += 1
    print(f"  消息{n}: {b.decode()[:60]}  (delivery_mode={h.delivery_mode})")
if n == 0:
    print("  (空)")

print("\n=== 结论 ===")
print("durable 队列 + delivery_mode=2 → 重启后消息存活")
print("durable 队列 + delivery_mode=1 → 重启后消息丢失（计数 1 → 0）")
c.close()
