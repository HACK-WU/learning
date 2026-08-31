#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""课5 知识点3 实测：三种队列类型的行为差异"""
import pika, time

CR = pika.PlainCredentials('learn', 'learn123')
CP = pika.ConnectionParameters(host='localhost', port=5672, credentials=CR)

def fresh():
    c = pika.BlockingConnection(CP)
    return c, c.channel()

# ---------- 1. classic：能不能被多次消费（读后即删）----------
print("=" * 60)
print("【classic】队列：消息被消费后是否还在？")
c, ch = fresh()
ch.queue_declare(queue='t_classic', durable=True, arguments={'x-queue-type':'classic'})
ch.basic_publish(exchange='', routing_key='t_classic', body='C1',
                 properties=pika.BasicProperties(delivery_mode=2))
ch.basic_publish(exchange='', routing_key='t_classic', body='C2',
                 properties=pika.BasicProperties(delivery_mode=2))
time.sleep(1)
r = ch.queue_declare(queue='t_classic', durable=True, passive=True)
print(f"  消费前消息数 = {r.method.message_count}")
m,h,b = ch.basic_get(queue='t_classic', auto_ack=True)
print(f"  取走一条: {b.decode()}")
r = ch.queue_declare(queue='t_classic', durable=True, passive=True)
print(f"  消费后消息数 = {r.method.message_count}  ← 减少，说明读后即删")
c.close()

# ---------- 2. stream：能不能重复读（可回放）----------
print("\n" + "=" * 60)
print("【stream】队列：能否重复消费（回放）？")
c, ch = fresh()
try:
    ch.queue_declare(queue='t_stream', durable=True, arguments={'x-queue-type':'stream'})
    ch.basic_publish(exchange='', routing_key='t_stream', body='S1',
                     properties=pika.BasicProperties(delivery_mode=2))
    time.sleep(1)
    r = ch.queue_declare(queue='t_stream', durable=True, passive=True)
    print(f"  消息数 = {r.method.message_count}")
    print("  stream 需专用协议(5552)消费；AMQP basic_get 对 stream 的行为如下：")
    m,h,b = ch.basic_get(queue='t_stream', auto_ack=True)
    print(f"    basic_get 结果: {b.decode() if b else None}")
except Exception as e:
    print(f"  异常: {type(e).__name__}: {str(getattr(e,'reply_text',e))[:200]}")
try: c.close()
except Exception: pass

# ---------- 3. quorum：常规读写 ----------
print("\n" + "=" * 60)
print("【quorum】队列：常规 AMQP 读写是否正常？")
c, ch = fresh()
try:
    ch.queue_declare(queue='t_quorum', durable=True, arguments={'x-queue-type':'quorum'})
    ch.basic_publish(exchange='', routing_key='t_quorum', body='Q1',
                     properties=pika.BasicProperties(delivery_mode=2))
    time.sleep(2)  # quorum 有 Raft 提交延迟
    r = ch.queue_declare(queue='t_quorum', durable=True, passive=True)
    print(f"  发送后消息数 = {r.method.message_count}")
    m,h,b = ch.basic_get(queue='t_quorum', auto_ack=True)
    print(f"  取到: {b.decode() if b else None}")
    r = ch.queue_declare(queue='t_quorum', durable=True, passive=True)
    print(f"  取走后消息数 = {r.method.message_count}")
except Exception as e:
    print(f"  异常: {type(e).__name__}: {str(getattr(e,'reply_text',e))[:200]}")
try: c.close()
except Exception: pass

# ---------- 4. stream 的限制：auto-delete / exclusive ----------
print("\n" + "=" * 60)
print("【stream】的限制：auto-delete / 非持久化")
c, ch = fresh()
for label, args in [
    ("stream + auto_delete=True", {'x-queue-type':'stream'}),
]:
    try:
        ch2 = c.channel()
        ch2.queue_declare(queue='t_stream_ad', durable=True, auto_delete=True, arguments=args)
        print(f"  {label}: 成功")
    except Exception as e:
        print(f"  {label}: 拒绝 → {str(getattr(e,'reply_text',e))[:120]}")
try: c.close()
except Exception: pass

# ---------- 5. quorum 的限制 ----------
print("\n" + "=" * 60)
print("【quorum】的限制：非持久化")
c, ch = fresh()
try:
    ch2 = c.channel()
    ch2.queue_declare(queue='t_quorum_trans', durable=False, exclusive=True,
                      arguments={'x-queue-type':'quorum'})
    print(f"  quorum + durable=False + exclusive=True: 成功")
except Exception as e:
    print(f"  quorum 非持久化: 拒绝 → code={getattr(e,'reply_code',None)} {str(getattr(e,'reply_text',e))[:120]}")
try: c.close()
except Exception: pass

# ---------- 6. 优先级/TTL 对 stream 的支持 ----------
print("\n" + "=" * 60)
print("【stream】是否支持 TTL / 优先级等特性")
c, ch = fresh()
try:
    ch2 = c.channel()
    ch2.queue_declare(queue='t_stream_ttl', durable=True,
                      arguments={'x-queue-type':'stream', 'x-message-ttl': 60000})
    print("  stream + x-message-ttl: 成功")
except Exception as e:
    print(f"  stream + x-message-ttl: 拒绝 → {str(getattr(e,'reply_text',e))[:150]}")
try: c.close()
except Exception: pass

print("\n完成")
