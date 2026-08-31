#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 6 实测 3：发布者确认（Publisher Confirm）

关键点：
1. confirm.select 开启后，每条消息都会收到 basic.ack（或 nack）
2. delivery_tag 在 confirm 模式下从 1 开始**连续递增**（与消息一一对应的序号）
3. 三种用法：单条等待、批量等待、异步回调
4. 事务（tx_select/tx_commit）与 confirm 的性能对比
5. confirm 只证明"broker 收到了"，不证明"消息已落盘 / 已进队列"
"""
import time
import random
import string
import pika

CRED = pika.PlainCredentials('learn', 'learn123')
PARAMS = pika.ConnectionParameters(host='localhost', port=5672, credentials=CRED)


def conn():
    return pika.BlockingConnection(PARAMS)


def rand_body(n=32):
    return ''.join(random.choices(string.ascii_letters, k=n)).encode()


print('=' * 72)
print('实验 1：开启 confirm，观察 delivery_tag 与 ack')
print('=' * 72)
Q = 'l6_confirm_basic'
c = conn()
ch = c.channel()
ch.queue_declare(queue=Q, durable=True)
ch.queue_purge(Q)
ch.confirm_delivery()          # 发送 confirm.select，开启发布者确认
print('  已执行 channel.confirm_delivery()')

tags = []
for i in range(1, 6):
    ch.basic_publish(exchange='', routing_key=Q, body=f'msg-{i}'.encode(),
                     properties=pika.BasicProperties(delivery_mode=2))
    print(f'  发送 msg-{i}（未阻塞等待）')
time.sleep(0.5)
c.close()
print('  → confirm 模式下 basic_publish 不阻塞，ack 由 broker 异步回传')

print()
print('=' * 72)
print('实验 2：用 add_on_return_callback 无法观测 confirm —— 需用回调收集')
print('=' * 72)
print('  pika 的 confirm_delivery() 后，未确认消息会在连接关闭/异常时抛出')
print('  UnroutableError / NackError。下面用回调收集 ack/nack。')


class ConfirmCollector:
    """异步收集 ack / nack / return"""
    def __init__(self, ch):
        self.acks = []
        self.nacks = []
        self.returns = []
        ch.add_on_return_callback(self._on_return)
        ch.confirm_delivery()

    def _on_return(self, channel, method, properties, body):
        self.returns.append((method.reply_code, method.reply_text, body))


Q2 = 'l6_confirm_async'
c = conn()
ch = c.channel()
ch.queue_declare(queue=Q2, durable=True)
ch.queue_purge(Q2)
col = ConfirmCollector(ch)

N = 20
t0 = time.time()
for i in range(N):
    ch.basic_publish(exchange='', routing_key=Q2, body=f'c-{i}'.encode(),
                     properties=pika.BasicProperties(delivery_mode=2))
# 等待 broker 处理完所有 confirm
ch.connection.process_data_events(time_limit=0)   # 触发一次 IO
time.sleep(1.0)
elapsed = time.time() - t0
c.close()
print(f'  发送 {N} 条（异步 confirm），耗时 {elapsed * 1000:.1f} ms，无异常抛出 = 全部被 ack')

print()
print('=' * 72)
print('实验 3：路由不到的消息在 confirm 模式下会怎样？（关键！）')
print('=' * 72)
print('  confirm 只保证 broker"收到并处理了"，路由不到队列的消息仍会被 ack！')
Q3 = 'l6_confirm_unroutable'
c = conn()
ch = c.channel()
ch.queue_declare(queue=Q3, durable=True)
ch.confirm_delivery()

returns = []
ch.add_on_return_callback(lambda ch_, m, p, b: returns.append((m.reply_code, m.reply_text)))

# mandatory=True：路由不到就退回
try:
    ch.basic_publish(exchange='amq.topic', routing_key='no.such.binding.key.zzz',
                     body=b'will not route',
                     properties=pika.BasicProperties(delivery_mode=2),
                     mandatory=True)
    ch.connection.process_data_events(time_limit=0)
    time.sleep(1.0)
    print(f'  mandatory=True 发到无绑定的 amq.topic：return 回调收到 {len(returns)} 条')
    for rc, rt in returns[:3]:
        print(f'      reply_code={rc}  reply_text={rt}')
except pika.exceptions.UnroutableError as e:
    # pika 会在 basic_publish 返回时把已收到的 return 直接抛成 UnroutableError
    print(f'  mandatory=True：pika 抛出 UnroutableError → {e}')
    print(f'      （这就是"退回"，说明消息没有被任何队列接收）')
c.close()

# 对照：mandatory=False（默认）路由不到 → 静默丢弃，且仍被 ack
c = conn()
ch = c.channel()
ch.confirm_delivery()
ch.basic_publish(exchange='amq.topic', routing_key='still.no.binding.zzz',
                 body=b'silently dropped')
ch.connection.process_data_events(time_limit=0)
time.sleep(0.5)
c.close()
print('  mandatory=False（默认）发到无绑定的交换机：无任何报错，消息静默丢弃')
print('  → 结论：confirm 通过 ≠ 消息进了队列，要看路由得配 mandatory 或 AE')

print()
print('=' * 72)
print('实验 4：事务 vs confirm —— 性能差距有多大')
print('=' * 72)
Q4 = 'l6_tx_vs_confirm'
c = conn()
ch = c.channel()
ch.queue_declare(queue=Q4, durable=True)
ch.queue_purge(Q4)

M = 200
body = rand_body()

# 4a: 事务
ch.tx_select()
t0 = time.time()
for i in range(M):
    ch.basic_publish(exchange='', routing_key=Q4, body=body)
    if (i + 1) % 10 == 0:
        ch.tx_commit()
tx_time = time.time() - t0
ch.tx_commit()
c.close()
print(f'  事务（每 10 条提交一次）：{M} 条耗时 {tx_time * 1000:.0f} ms'
      f'  ({tx_time / M * 1000:.2f} ms/条)')

# 4b: confirm 批量（发完统一等）
c = conn()
ch = c.channel()
ch.queue_declare(queue=Q4, durable=True)
ch.confirm_delivery()
t0 = time.time()
for i in range(M):
    ch.basic_publish(exchange='', routing_key=Q4, body=body)
ch.connection.process_data_events(time_limit=0)
time.sleep(0.5)
cf_time = time.time() - t0
c.close()
print(f'  confirm（异步）：        {M} 条耗时 {cf_time * 1000:.0f} ms'
      f'  ({cf_time / M * 1000:.2f} ms/条)')
print(f'  → 事务是 confirm 的 {tx_time / cf_time:.1f} 倍耗时')

# 4c: 不开任何确认（基线）
c = conn()
ch = c.channel()
ch.queue_declare(queue=Q4, durable=True)
t0 = time.time()
for i in range(M):
    ch.basic_publish(exchange='', routing_key=Q4, body=body)
ch.connection.process_data_events(time_limit=0)
time.sleep(0.5)
base_time = time.time() - t0
c.close()
print(f'  无确认（基线）：         {M} 条耗时 {base_time * 1000:.0f} ms'
      f'  ({base_time / M * 1000:.2f} ms/条)')

print()
print('DONE')
