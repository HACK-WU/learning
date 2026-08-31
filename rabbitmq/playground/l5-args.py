#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""课5 知识点1 实测：arguments 常用参数（TTL / 长度限制 / 优先级 / 队列TTL）"""
import pika, time

CR = pika.PlainCredentials('learn', 'learn123')
CP = pika.ConnectionParameters(host='localhost', port=5672, credentials=CR)

def fresh():
    c = pika.BlockingConnection(CP)
    return c, c.channel()

def depth(ch, q):
    r = ch.queue_declare(queue=q, passive=True)
    return r.method.message_count

# ---------- 1. x-max-length：队列长度限制 ----------
print("=" * 62)
print("【x-max-length】队列最多存 N 条，超出怎么办")
c, ch = fresh()
ch.queue_declare(queue='a_maxlen', durable=True,
                 arguments={'x-queue-type': 'classic', 'x-max-length': 3})
for i in range(1, 6):
    ch.basic_publish(exchange='', routing_key='a_maxlen', body=f'm{i}')
time.sleep(1)
print(f"  发了 5 条，队列深度 = {depth(ch, 'a_maxlen')}  ← 3 表示多余的被丢弃(drop-head 默认)")
while True:
    m, h, b = ch.basic_get(queue='a_maxlen', auto_ack=True)
    if not m: break
    print(f"    剩余消息: {b.decode()}")
c.close()

# ---------- 2. x-message-ttl：消息级 TTL ----------
print("\n" + "=" * 62)
print("【x-message-ttl】队列级消息存活时间（1500 毫秒）")
c, ch = fresh()
ch.queue_declare(queue='a_ttl', durable=True,
                 arguments={'x-queue-type': 'classic', 'x-message-ttl': 1500})
ch.basic_publish(exchange='', routing_key='a_ttl', body='will-expire')
time.sleep(0.5)
print(f"  0.5 秒后深度 = {depth(ch, 'a_ttl')}")
time.sleep(2)
print(f"  2.5 秒后深度 = {depth(ch, 'a_ttl')}  ← 0 表示过期被清除")
c.close()

# ---------- 3. x-expires：队列自身多久没用就删 ----------
print("\n" + "=" * 62)
print("【x-expires】队列空闲多久自动删除（2000 毫秒）")
c, ch = fresh()
ch.queue_declare(queue='a_expires', durable=True,
                 arguments={'x-queue-type': 'classic', 'x-expires': 2000})
print(f"  刚声明，深度查询: {depth(ch, 'a_expires')}")
time.sleep(3.5)
c2, ch2 = fresh()
try:
    ch2.queue_declare(queue='a_expires', passive=True)
    print("  3.5 秒后：队列仍存在")
except Exception as e:
    print(f"  3.5 秒后：队列已消失 → {type(e).__name__} code={getattr(e,'reply_code',None)}")
c2.close(); c.close()

# ---------- 4. x-max-priority：优先级队列 ----------
print("\n" + "=" * 62)
print("【x-max-priority】优先级队列")
c, ch = fresh()
ch.queue_declare(queue='a_prio', durable=True,
                 arguments={'x-queue-type': 'classic', 'x-max-priority': 10})
# 先塞低优先级，再塞高优先级
for p, body in [(1, 'low-1'), (1, 'low-2'), (9, 'high-1')]:
    ch.basic_publish(exchange='', routing_key='a_prio', body=body,
                     properties=pika.BasicProperties(priority=p))
time.sleep(1)
print("  发送顺序: low-1(p1), low-2(p1), high-1(p9)")
print("  取出顺序:")
order = []
while True:
    m, h, b = ch.basic_get(queue='a_prio', auto_ack=True)
    if not m: break
    order.append(f"{b.decode()}(p{h.priority})")
print(f"    {order}  ← high-1 是否排到前面")
c.close()

# ---------- 5. 各类参数在 quorum / stream 上的支持度 ----------
print("\n" + "=" * 62)
print("【参数支持度】x-message-ttl 在 quorum / stream 上")
for qt in ['quorum', 'stream']:
    c, ch = fresh()
    try:
        ch2 = c.channel()
        ch2.queue_declare(queue=f'a_ttl_{qt}', durable=True,
                          arguments={'x-queue-type': qt, 'x-message-ttl': 60000})
        print(f"  {qt} + x-message-ttl: ✅ 支持")
    except Exception as e:
        txt = str(getattr(e, 'reply_text', e))
        print(f"  {qt} + x-message-ttl: ❌ 拒绝 → {txt[:90]}")
    try: c.close()
    except Exception: pass

print("\n" + "=" * 62)
print("【参数支持度】x-max-length 在 quorum / stream 上")
for qt in ['quorum', 'stream']:
    c, ch = fresh()
    try:
        ch2 = c.channel()
        ch2.queue_declare(queue=f'a_len_{qt}', durable=True,
                          arguments={'x-queue-type': qt, 'x-max-length': 100})
        print(f"  {qt} + x-max-length: ✅ 支持")
    except Exception as e:
        txt = str(getattr(e, 'reply_text', e))
        print(f"  {qt} + x-max-length: ❌ 拒绝 → {txt[:90]}")
    try: c.close()
    except Exception: pass

print("\n完成")
