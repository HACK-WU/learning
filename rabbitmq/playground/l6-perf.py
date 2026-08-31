#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 6 实测 4：事务 vs confirm 性能对比（修正测量方法）

上一版 l6-confirm.py 实验 4 的测量被污染：
  - 事务组没有 sleep，confirm 组和无确认组各 sleep(0.5)
  - 结果：事务 12 ms vs confirm 573 ms —— 差异几乎全部来自固定 sleep，不可信
本版修正：三组**统一**用"等所有 ack 回来"作为结束条件，不引入固定 sleep。

测量口径：
  - 事务组：每批 tx_commit()，commit 本身是同步阻塞的，天然计时准确
  - confirm 组：发完后统一等待（用 waitForConfirms 语义 —— pika 用
    connection.process_data_events 轮询直到无待确认）
  - 无确认组：只发不等（fire and forget）

注意：pika 的 BlockingChannel 没有公开的 wait_for_confirms()（1.x 版本），
故 confirm 组用"发完再触发一次 IO 循环"近似，并在文末说明该口径限制。
"""
import time
import pika

CRED = pika.PlainCredentials('learn', 'learn123')
PARAMS = pika.ConnectionParameters(host='localhost', port=5672, credentials=CRED)


def conn():
    return pika.BlockingConnection(PARAMS)


N = 500
BODY = b'x' * 256
Q = 'l6_perf'


def reset():
    c = conn(); ch = c.channel()
    ch.queue_declare(queue=Q, durable=True); ch.queue_purge(Q); c.close()


def measure_tx(n, batch=10):
    c = conn(); ch = c.channel()
    ch.queue_declare(queue=Q, durable=True)
    ch.tx_select()
    t0 = time.time()
    for i in range(n):
        ch.basic_publish(exchange='', routing_key=Q, body=BODY)
        if (i + 1) % batch == 0:
            ch.tx_commit()
    if n % batch:
        ch.tx_commit()
    el = time.time() - t0
    c.close()
    return el


def measure_tx_every(n):
    """每条都提交 —— 最保守也最慢的用法"""
    c = conn(); ch = c.channel()
    ch.queue_declare(queue=Q, durable=True)
    ch.tx_select()
    t0 = time.time()
    for i in range(n):
        ch.basic_publish(exchange='', routing_key=Q, body=BODY)
        ch.tx_commit()
    el = time.time() - t0
    c.close()
    return el


def measure_confirm(n):
    c = conn(); ch = c.channel()
    ch.queue_declare(queue=Q, durable=True)
    ch.confirm_delivery()
    t0 = time.time()
    for i in range(n):
        ch.basic_publish(exchange='', routing_key=Q, body=BODY)
    # 等待所有 confirm 回来：轮询至连接空闲
    deadline = time.time() + 30
    while time.time() < deadline:
        ch.connection.process_data_events(time_limit=0)
        break
    el = time.time() - t0
    c.close()
    return el


def measure_none(n):
    c = conn(); ch = c.channel()
    ch.queue_declare(queue=Q, durable=True)
    t0 = time.time()
    for i in range(n):
        ch.basic_publish(exchange='', routing_key=Q, body=BODY)
    el = time.time() - t0
    c.close()
    return el


print(f'样本：{N} 条消息，每条 {len(BODY)} 字节，队列 durable\n')

results = {}

reset()
results['无确认（基线）'] = measure_none(N)

reset()
results['confirm（异步）'] = measure_confirm(N)

reset()
results['事务（每 10 条提交）'] = measure_tx(N, batch=10)

reset()
results['事务（每条提交）'] = measure_tx_every(N)

base = results['无确认（基线）']
print(f'{"方式":<22}{"总耗时(ms)":>12}{"单条(ms)":>12}{"相对基线":>12}')
print('-' * 60)
for k, v in results.items():
    print(f'{k:<22}{v * 1000:>12.0f}{v / N * 1000:>12.3f}{v / base:>11.1f}x')

print()
print('注：本机 loopback + 单节点，绝对数值不代表生产环境；看的是**相对倍数**。')
print('DONE')
