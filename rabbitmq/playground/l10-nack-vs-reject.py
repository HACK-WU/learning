#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 10 实验 4：nack vs reject —— 谁才让延迟递增？（4.3 语义核心）
================================================================
按 RabbitMQ 4.3 官方文档的判定表：

| 触发方式                    | acquired-count | delivery-count |
|-----------------------------|----------------|----------------|
| AMQP 0.9.1 basic.nack       | ✅ +1          | ❌ 不变        |
| AMQP 0.9.1 basic.reject     | ✅ +1          | ✅ +1          |

而延迟计算公式是：
    delay = min(delayed_retry_min * **delivery_count**, max)

⚠️ 推论（本实验要验证）：
  用 basic.nack 返回 → delivery-count 不涨 → 延迟恒为 min，不递增
  用 basic.reject 返回 → delivery-count 涨 → 延迟线性递增

但 l10-retry-multiroound.py 实测显示 nack 后 x-acquired-count 始终为 0，
这与"nack 使 acquired-count +1"的文档说法也不符。本实验做严格对照。

方法：连续对同一条消息做 N 次返回，每次记录：
  - 再次可投递的等待时长
  - 消息 headers（x-acquired-count / x-delivery-count）
"""
import sys
import time

import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')
Q = 'l10.nackreject'


def conn_of():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=300))


def run(mode, rounds=4, rmin=3000, rmax=12000):
    """mode: 'nack' | 'reject'"""
    c = conn_of()
    ch = c.channel()
    try:
        ch.queue_delete(queue=Q)
    except Exception:
        pass
    ch.queue_declare(
        queue=Q, durable=True,
        arguments={
            'x-queue-type': 'quorum',
            'x-delayed-retry-type': 'all',
            'x-delayed-retry-min': rmin,
            'x-delayed-retry-max': rmax,
            'x-delivery-limit': 20,
        })
    ch.basic_publish(exchange='', routing_key=Q, body=b'nr-probe',
                     properties=pika.BasicProperties(delivery_mode=2))
    time.sleep(1)

    rows = []
    for rnd in range(1, rounds + 1):
        m = ch.basic_get(Q, auto_ack=False)
        if m[0] is None:
            rows.append((rnd, None, None, None))
            break
        method, props, body = m
        hdrs = props.headers or {}
        acq = hdrs.get('x-acquired-count')
        dc = hdrs.get('x-delivery-count')

        t0 = time.time()
        if mode == 'nack':
            ch.basic_nack(method.delivery_tag, requeue=True)
        else:
            ch.basic_reject(method.delivery_tag, requeue=True)

        waited = None
        for _ in range(120):        # 最多等 36 秒
            time.sleep(0.3)
            mm = ch.basic_get(Q, auto_ack=False)
            if mm[0] is not None:
                waited = time.time() - t0
                # 取出后立刻 ack，只记录耗时；下一轮用同一条继续
                ch.basic_ack(mm[0].delivery_tag)
                ch.basic_publish(exchange='', routing_key=Q, body=b'nr-probe',
                                 properties=pika.BasicProperties(
                                     delivery_mode=2))
                break
        rows.append((rnd, waited, acq, dc))

    try:
        ch.queue_delete(queue=Q)
    except Exception:
        pass
    c.close()
    return rows


def main():
    print("=" * 74)
    print("课 10 实验 4：nack vs reject 对延迟退避的影响")
    print("=" * 74)
    print("配置：type=all, min=3000ms, max=12000ms, delivery-limit=20")
    print("环境：RabbitMQ 4.3.5 / pika %s\n" % pika.__version__)

    for mode in ('nack', 'reject'):
        print("-" * 74)
        print("【%s】连续返回同一条消息" % mode.upper())
        print("-" * 74)
        rows = run(mode, rounds=4)
        print("")
        print("| 轮次 | 再次可投递耗时 | x-acquired-count | x-delivery-count |")
        print("|------|----------------|------------------|------------------|")
        for rnd, waited, acq, dc in rows:
            if waited is None:
                print("| %d | 超时/无消息 | %s | %s |" % (rnd, acq, dc))
            else:
                print("| %d | %.2f s | %s | %s |" % (rnd, waited, acq, dc))
        print("")

    print("=" * 74)
    print("判定")
    print("=" * 74)
    print("若 nack 的耗时恒定在 min、reject 的耗时逐轮递增，")
    print("则证明 4.3 的语义：nack 不算'投递失败'，只 reject / 通道崩溃")
    print("才让 delivery-count 增长并放大延迟。")

    return 0


if __name__ == '__main__':
    sys.exit(main())
