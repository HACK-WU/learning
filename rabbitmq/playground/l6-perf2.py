#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 6 实测 5：为什么"confirm 应该比事务快"实测却是反的？

l6-perf.py 的结果与官方文档/常见说法相反：
    无确认            10 ms   1.0x
    confirm（异步）   120 ms  11.8x
    事务（每10条）     25 ms   2.5x
   事务（每条提交）   136 ms  13.4x

假设：**pika 的 BlockingChannel 在开启 confirm 后，basic_publish 会强制一次
网络往返（flush + 等 ack）**，导致 confirm 退化成"每条一个 RTT"——
这与 AMQP 协议设计的"流水线式异步确认"完全不同，是 **pika 客户端实现特征**，
不是协议本身的性质。

验证方法：
  1. 测纯 RTT（一次 publish + 一次 tx_commit，N 次）作为 1 个 RTT 的基准成本
  2. 若 confirm 单条耗时 ≈ 1 个 RTT，则假设成立
  3. 测 tx 一次性提交全部（batch=N）作为"最理想事务"下限
  4. 对比不同 N 下 confirm 是否线性增长（若是 → 每条一个 RTT）
"""
import time
import pika

CRED = pika.PlainCredentials('learn', 'learn123')
PARAMS = pika.ConnectionParameters(host='localhost', port=5672, credentials=CRED)
BODY = b'x' * 256
Q = 'l6_perf2'


def conn():
    return pika.BlockingConnection(PARAMS)


def reset():
    c = conn(); ch = c.channel()
    ch.queue_declare(queue=Q, durable=True); ch.queue_purge(Q); c.close()


def rtt_cost(n):
    """测 1 次网络往返的成本：每条消息 publish 后立刻 tx_commit（一次 commit = 一次 RTT）"""
    c = conn(); ch = c.channel()
    ch.queue_declare(queue=Q, durable=True)
    ch.tx_select()
    t0 = time.time()
    for _ in range(n):
        ch.basic_publish(exchange='', routing_key=Q, body=BODY)
        ch.tx_commit()
    el = time.time() - t0
    c.close()
    return el / n


def tx_single_commit(n):
    """全部发完只提交一次 —— 事务的理论最快用法（1 次 RTT）"""
    c = conn(); ch = c.channel()
    ch.queue_declare(queue=Q, durable=True)
    ch.tx_select()
    t0 = time.time()
    for _ in range(n):
        ch.basic_publish(exchange='', routing_key=Q, body=BODY)
    ch.tx_commit()
    el = time.time() - t0
    c.close()
    return el


def confirm_async(n):
    c = conn(); ch = c.channel()
    ch.queue_declare(queue=Q, durable=True)
    ch.confirm_delivery()
    t0 = time.time()
    for _ in range(n):
        ch.basic_publish(exchange='', routing_key=Q, body=BODY)
    el = time.time() - t0
    c.close()
    return el


def no_confirm(n):
    c = conn(); ch = c.channel()
    ch.queue_declare(queue=Q, durable=True)
    t0 = time.time()
    for _ in range(n):
        ch.basic_publish(exchange='', routing_key=Q, body=BODY)
    el = time.time() - t0
    c.close()
    return el


N = 300
reset()
rtt = rtt_cost(N)
print(f'基准：1 次网络往返（publish + tx_commit）≈ {rtt * 1000:.3f} ms\n')

print(f'{"N":>5}{"无确认(ms)":>12}{"confirm(ms)":>12}{"confirm/条(ms)":>16}{"条/ RTT":>10}')
print('-' * 60)
for n in (100, 300, 600):
    reset()
    nc = no_confirm(n)
    reset()
    cf = confirm_async(n)
    per = cf / n
    print(f'{n:>5}{nc * 1000:>12.1f}{cf * 1000:>12.1f}{per * 1000:>16.3f}{per / rtt:>10.2f}')

print()
print('若"confirm/条 ÷ 1 次 RTT ≈ 1.0" → pika 每条 publish 都在等一次往返，')
print('即 confirm 在 pika BlockingChannel 上**退化成了同步逐条确认**。')
print()

reset()
tx1 = tx_single_commit(600)
reset()
nc600 = no_confirm(600)
reset()
cf600 = confirm_async(600)
print(f'600 条对比：')
print(f'  无确认                    {nc600 * 1000:8.1f} ms  ({nc600 / nc600:.1f}x)')
print(f'  事务（600 条只提交 1 次）  {tx1 * 1000:8.1f} ms  ({tx1 / nc600:.1f}x)  ← 只有 1 次 RTT')
print(f'  confirm（pika 异步）      {cf600 * 1000:8.1f} ms  ({cf600 / nc600:.1f}x)  ← 实际每条 1 次 RTT')
print()
print('DONE')
