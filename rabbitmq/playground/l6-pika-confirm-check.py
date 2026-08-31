#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 6 实测 6：pika BlockingChannel 的 confirm 到底是同步还是异步？

背景冲突：
  - 官方文档（blog.rabbitmq.com/docs/4.0/confirms）：confirm 是**异步**的，
    事务使吞吐下降 250 倍，confirm 是推荐方案。
  - 本机实测（l6-perf2.py）：pika confirm 单条耗时 ≈ 1 个 RTT，
    事务"批量提交"反而比 confirm 快。

假设：pika 的 **BlockingChannel** 在 confirm 模式下，basic_publish 内部会
      flush 并等待该条的 ack —— 即"同步逐条确认"，与协议设计相反。
      这是**客户端适配器实现特征**，不是 AMQP/RabbitMQ 的性质。

验证手段：
  1. 直接读 pika 源码，找 BlockingChannel.basic_publish 在 confirm 模式下的分支
  2. 检查是否有 wait_for_confirms / 批量确认 API
  3. 用 SelectConnection（异步适配器）跑一次，看是否真的能流水线化
"""
import inspect
import time
import pika
from pika.adapters.blocking_connection import BlockingChannel

print('=' * 72)
print('1) pika 版本与 BlockingChannel.basic_publish 源码')
print('=' * 72)
print(f'  pika {pika.__version__}')

src = inspect.getsource(BlockingChannel.basic_publish)
lines = src.splitlines()
# 只打印关键分支（confirm / flush / wait）
keep = []
for i, ln in enumerate(lines):
    s = ln.strip()
    if any(k in s for k in ('_flush_output', 'confirm', 'wait', 'Confirm',
                            'def basic_publish', 'unconfirmed', 'returned')):
        keep.append(ln)
print('\n'.join('  ' + l for l in keep[:45]))

print()
print('=' * 72)
print('2) BlockingChannel 是否提供 wait_for_confirms 类 API？')
print('=' * 72)
apis = [m for m in dir(BlockingChannel) if 'confirm' in m.lower()
        or 'wait' in m.lower()]
print(f'  匹配 confirm/wait 的方法: {apis}')

print()
print('=' * 72)
print('3) 协议层：basic_publish 后 broker 是否立即回 ack？（抓帧级时序）')
print('=' * 72)
print('  用两个连接对比：')
print('  - 连接 A：confirm 模式，连续 publish 100 条，测总时间')
print('  - 连接 B：confirm 模式，publish 1 条后强制 process_data_events，循环 100 次')
print('  若两者接近 → 说明每条都在等 RTT（同步），无法流水线')

CRED = pika.PlainCredentials('learn', 'learn123')
PARAMS = pika.ConnectionParameters(host='localhost', port=5672, credentials=CRED)
BODY = b'x' * 256
Q = 'l6_pika_sync'


def reset():
    c = pika.BlockingConnection(PARAMS); ch = c.channel()
    ch.queue_declare(queue=Q, durable=True); ch.queue_purge(Q); c.close()


def no_wait(n):
    c = pika.BlockingConnection(PARAMS); ch = c.channel()
    ch.queue_declare(queue=Q, durable=True)
    ch.confirm_delivery()
    t0 = time.time()
    for _ in range(n):
        ch.basic_publish(exchange='', routing_key=Q, body=BODY)
    el = time.time() - t0
    c.close()
    return el


def with_yield(n):
    c = pika.BlockingConnection(PARAMS); ch = c.channel()
    ch.queue_declare(queue=Q, durable=True)
    ch.confirm_delivery()
    t0 = time.time()
    for _ in range(n):
        ch.basic_publish(exchange='', routing_key=Q, body=BODY)
        ch.connection.process_data_events(time_limit=0)
    el = time.time() - t0
    c.close()
    return el


N = 200
reset()
a = no_wait(N)
reset()
b = with_yield(N)
print(f'  连续 publish {N} 条（不插 IO）      : {a * 1000:8.1f} ms  ({a / N * 1000:.3f} ms/条)')
print(f'  每条 publish 后强制 IO {N} 条        : {b * 1000:8.1f} ms  ({b / N * 1000:.3f} ms/条)')
print(f'  → 比值 {a / b:.2f}：接近 1.0 说明不插 IO 时 pika 也已在内部等待 ack')

print()
print('DONE')
