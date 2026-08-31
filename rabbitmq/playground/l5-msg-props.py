#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""课5 知识点2 实测：消息属性 —— delivery_mode / headers / properties / 大小限制"""
import pika, json, time

CR = pika.PlainCredentials('learn', 'learn123')
CP = pika.ConnectionParameters(host='localhost', port=5672, credentials=CR)

c = pika.BlockingConnection(CP)
ch = c.channel()

# ========== 发送端：带全套属性的消息 ==========
ch.queue_declare(queue='l5_props_q', durable=True, arguments={'x-queue-type': 'classic'})

props = pika.BasicProperties(
    delivery_mode=2,                      # 持久化标记
    content_type='application/json',
    content_encoding='utf-8',
    headers={'order_id': 'A1001', 'trace': 'abc-123', 'retry': 0},
    message_id='msg-0001',
    correlation_id='corr-0001',
    timestamp=int(time.time()),
    expiration='60000',                   # 消息级 TTL 60 秒
    app_id='lesson05-demo',
    user_id='learn',                      # 校验必须为当前登录用户
    priority=5,
    reply_to='l5_reply_q',
    type='order.created',
)
body = json.dumps({'sku': 'BOOK-001', 'qty': 2})

print("===== 发送消息，属性如下 =====")
for k in ['delivery_mode','content_type','content_encoding','headers','message_id',
          'correlation_id','timestamp','expiration','app_id','user_id','priority',
          'reply_to','type']:
    print(f"  {k:18} = {getattr(props, k)}")

ch.basic_publish(exchange='', routing_key='l5_props_q', body=body, properties=props)
print("\n消息已发送")

# ========== 接收端：读取属性 ==========
time.sleep(0.5)
print("\n===== 接收到的消息属性 =====")
method, header, recv_body = ch.basic_get(queue='l5_props_q', auto_ack=True)
if method:
    print(f"  body                = {recv_body.decode()}")
    print(f"  delivery_tag        = {method.delivery_tag}")
    print(f"  routing_key         = {method.routing_key}")
    print(f"  exchange            = {method.exchange!r}")
    print(f"  redelivered         = {method.redelivered}")
    for k in ['delivery_mode','content_type','content_encoding','headers','message_id',
              'correlation_id','timestamp','expiration','app_id','user_id','priority',
              'reply_to','type']:
        print(f"  {k:18} = {getattr(header, k)}")
else:
    print("未收到消息")

# ========== 对照：delivery_mode=1（不持久化）==========
print("\n===== 对照：delivery_mode=1 =====")
ch.basic_publish(exchange='', routing_key='l5_props_q', body=b'transient msg',
                 properties=pika.BasicProperties(delivery_mode=1))
time.sleep(0.5)
m, h, b = ch.basic_get(queue='l5_props_q', auto_ack=True)
print(f"  delivery_mode = {h.delivery_mode if h else None}  (1=不持久化)")

# ========== 关键：不设置 delivery_mode 时的默认值 ==========
print("\n===== 关键：完全不设置 properties 时，delivery_mode 默认是多少？=====")
ch.basic_publish(exchange='', routing_key='l5_props_q', body=b'no props at all')
time.sleep(0.5)
m2, h2, b2 = ch.basic_get(queue='l5_props_q', auto_ack=True)
print(f"  delivery_mode = {h2.delivery_mode if h2 else None}")
print(f"  ← 注意：None 表示服务端没回传该字段，不等于 1")

# ========== user_id 校验：改成别人的名字应被拒绝 ==========
print("\n===== user_id 校验：冒充他人身份 =====")
try:
    ch2 = c.channel()
    ch2.confirm_delivery()  # 打开发布确认，才能收到 broker 的 Nack
    ch2.basic_publish(exchange='', routing_key='l5_props_q', body=b'fake user',
                      properties=pika.BasicProperties(delivery_mode=2, user_id='admin'))
    print(">>> 发送调用未抛异常")
except Exception as e:
    print(f">>> 异常: {type(e).__name__}: {e}")

c.close()
print("\n===== 完成 =====")
