#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""课5 知识点1 实测（v3）：auto-delete 语义 —— 最后一个消费者断开后删除"""
import pika, time

CR = pika.PlainCredentials('learn', 'learn123')
CP = pika.ConnectionParameters(host='localhost', port=5672, credentials=CR)

def new_conn():
    return pika.BlockingConnection(CP)

def show(t):
    print(f"\n===== {t} =====")

# 声明一个 auto-delete 队列
c, ch = new_conn(), None
ch = c.channel()
ch.queue_declare(queue='l5_ad_q', durable=True, auto_delete=True,
                 arguments={'x-queue-type': 'classic'})
print("已声明 l5_ad_q (durable=True, auto_delete=True)")

def q_exists(name):
    """用 passive 声明探测队列是否存在"""
    c2 = new_conn(); ch2 = c2.channel()
    try:
        ch2.queue_declare(queue=name, passive=True)
        c2.close()
        return True
    except Exception:
        try: c2.close()
        except Exception: pass
        return False

show("步骤1：刚声明完，队列是否存在")
print(f"l5_ad_q 存在? {q_exists('l5_ad_q')}")

show("步骤2：启动一个消费者（basic_consume）")
consumer_conn = new_conn()
cch = consumer_conn.channel()
cch.queue_declare(queue='l5_ad_q', durable=True, auto_delete=True)
result = cch.basic_consume(queue='l5_ad_q', on_message_callback=lambda *a: None, auto_ack=True)
print(f"消费者已启动 (consumer_tag={result})")

show("步骤3：消费者断开连接，观察队列是否被删除")
try:
    consumer_conn.close()
    print("消费者连接已关闭")
except Exception as e:
    print(f"关闭异常: {e}")
time.sleep(2)
print(f"l5_ad_q 存在? {q_exists('l5_ad_q')}  ← False 说明 auto-delete 生效")

# 对照：非 auto-delete 队列
show("对照组：非 auto-delete 队列消费者断开后仍在")
c3 = new_conn(); ch3 = c3.channel()
ch3.queue_declare(queue='l5_noad_q', durable=True, auto_delete=False)
cch3 = c3.channel()
cch3.basic_consume(queue='l5_noad_q', on_message_callback=lambda *a: None, auto_ack=True)
try:
    c3.close()
except Exception:
    pass
time.sleep(2)
print(f"l5_noad_q 存在? {q_exists('l5_noad_q')}  ← True 说明队列保留")

# 再验 auto-delete 队列"从未有消费者"时的行为
show("补充：auto-delete 队列声明后从未被消费，会立刻删除吗？")
c4 = new_conn(); ch4 = c4.channel()
ch4.queue_declare(queue='l5_ad_never', durable=True, auto_delete=True)
time.sleep(1)
print(f"l5_ad_never 存在? {q_exists('l5_ad_never')}  ← True 说明只有'曾有过消费者 + 最后一个断开'才删")
try:
    c4.close()
except Exception:
    pass

print("\n===== 全部完成 =====")
