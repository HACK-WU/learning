#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""课5 知识点2 实测（v4）：消息大小限制 —— 完整结论"""
import pika, time

CR = pika.PlainCredentials('learn', 'learn123')
CP = pika.ConnectionParameters(host='localhost', port=5672, credentials=CR)
Q = 'l5_size_test'
MAX = 16777216

def fresh():
    c = pika.BlockingConnection(CP)
    return c, c.channel()

def depth(ch):
    r = ch.queue_declare(queue=Q, durable=True, passive=True)
    return r.method.message_count

# 清理
c, ch = fresh()
ch.queue_declare(queue=Q, durable=True, arguments={'x-queue-type':'classic'})
while True:
    m,h,b = ch.basic_get(queue=Q, auto_ack=True)
    if not m: break
print(f"基线队列深度 = {depth(ch)}")
c.close()

# ===== 结论1：未超限大消息可正常收发 =====
c, ch = fresh()
ch.basic_publish(exchange='', routing_key=Q, body=b'y'*(5*1024*1024))
time.sleep(2)
print(f"\n[结论1] 5 MiB 消息：进队列，深度 = {depth(ch)}")
m,h,b = ch.basic_get(queue=Q, auto_ack=True)
print(f"        取出长度 = {len(b)} bytes")
c.close()

# ===== 结论2：超限消息 → channel 级 406 错误，channel 被关闭 =====
print(f"\n[结论2] 发送 {MAX+1} 字节（超限 1 字节）")
c, ch = fresh()
try:
    ch.basic_publish(exchange='', routing_key=Q, body=b'x'*(MAX+1))
    print("        publish 调用同步返回（未立刻抛异常）")
    time.sleep(2)
    print(f"        队列深度 = {depth(ch)}  ← 报错说明 channel 已关")
except Exception as e:
    print(f"        异常: {type(e).__name__}")
    print(f"        code={getattr(e,'reply_code',None)}")
    print(f"        text={getattr(e,'reply_text',str(e))}")
print(f"        连接是否存活? {c.is_open}  ← True 说明是【channel 级】错误，不是连接级")
try: c.close()
except Exception: pass

# ===== 结论3：超限后必须用新 channel 才能继续 =====
print("\n[结论3] 超限后用新 channel 继续操作")
c, ch = fresh()
print(f"        新 channel 可用，队列深度 = {depth(ch)}")
c.close()

# ===== 结论4：confirm 模式下能否捕获 =====
print("\n[结论4] 开启 publisher confirm 后发送超限消息")
c, ch = fresh()
try:
    ch.confirm_delivery()
    ch.basic_publish(exchange='', routing_key=Q, body=b'z'*(MAX+100))
    print("        publish 返回，未抛异常")
    time.sleep(2)
    print(f"        队列深度 = {depth(ch)}")
except Exception as e:
    print(f"        异常: {type(e).__name__}: {str(getattr(e,'reply_text',e))[:150]}")
try: c.close()
except Exception: pass

# ===== 最终确认：超限消息从未入队 =====
c, ch = fresh()
print(f"\n[最终] {Q} 深度 = {depth(ch)}  ← 0 表示超限消息从未进入队列")
c.close()
print("\n完成")
