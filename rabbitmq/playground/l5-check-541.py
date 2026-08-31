#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""确认 P0：裸 queue_declare(queue='order_queue') 在 4.3 上的真实结果"""
import pika

CR = pika.PlainCredentials('learn', 'learn123')
CP = pika.ConnectionParameters(host='localhost', port=5672, credentials=CR)

# 先删掉可能存在的队列
c = pika.BlockingConnection(CP)
ch = c.channel()
try:
    ch.queue_delete(queue='order_queue')
    print("已删除遗留的 order_queue")
except Exception:
    print("order_queue 原本不存在")
c.close()

print("\n=== 复现第一幕/第二幕的写法：裸 queue_declare ===")
c = pika.BlockingConnection(CP)
ch = c.channel()
try:
    ch.queue_declare(queue='order_queue')
    print(">>> 声明成功（与预期不符）")
    ch.basic_publish(exchange='', routing_key='order_queue', body='order-001')
    print(">>> 发送成功")
except Exception as e:
    print(f">>> 失败: {type(e).__name__} code={getattr(e,'reply_code',None)}")
    print(f">>> {str(getattr(e,'reply_text',e)).splitlines()[0]}")
print(f">>> 连接是否已关闭? {not c.is_open}")
try: c.close()
except Exception: pass

print("\n=== 结论 ===")
print("若上面是 541，则课5第一幕/第二幕中『裸声明能跑通、只是消息丢』的叙事不成立")
print("正确叙事应为：裸声明在 4.3 上直接被拒（课3 已教），必须 durable=True；")
print("而『队列 durable 但消息非持久 → 重启丢消息』才是本课的新冲突")
