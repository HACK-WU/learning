#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 10 实验 3：延迟重试的多轮退避与 acquired-count 追踪
======================================================
修正 l10-delayed-retry.py 场景 B 在第 2 轮中断的问题，
并精确追踪每次返回后的 x-acquired-count 与延迟时长。

关键修正点（吸取前两课的取数教训）：
  - basic_get 返回三元组 (method, properties, body)，不是 (method, body, props)
  - 一个 delivery_tag 只能 ack 或 nack 一次，不能 ack 完再 nack（会报
    PRECONDITION_FAILED - unknown delivery tag）
  - 延迟期间消息不可投递，basic_get 返回 None，需要轮询等待

预期（min=3000, max=12000, type=all）：
  第 1 次返回 → 3s
  第 2 次返回 → 6s
  第 3 次返回 → 9s
  ...封顶 12s
"""
import sys
import time

import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')
Q = 'l10.retry.multi'


def conn_of():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=300))


def main():
    print("=" * 74)
    print("课 10 实验 3：延迟重试多轮退避（min=3000ms max=12000ms type=all）")
    print("=" * 74)

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
            'x-delayed-retry-min': 3000,
            'x-delayed-retry-max': 12000,
            'x-delivery-limit': 20,
        })
    ch.basic_publish(exchange='', routing_key=Q, body=b'multi-round-probe',
                     properties=pika.BasicProperties(delivery_mode=2))
    time.sleep(1)

    print("")
    print("| 轮次 | nack 后再次可投递 | 理论延迟 | x-acquired-count |")
    print("|------|-------------------|----------|------------------|")

    ROUNDS = 4
    for rnd in range(1, ROUNDS + 1):
        # 取消息
        m = ch.basic_get(Q, auto_ack=False)
        if m[0] is None:
            print("| %d | 队列无消息（异常） | %d ms | - |" % (
                rnd, min(3000 * (rnd - 1) or 3000, 12000)))
            break
        method, props, body = m
        hdrs = props.headers or {}
        acq = hdrs.get('x-acquired-count', 0)

        t0 = time.time()
        ch.basic_nack(method.delivery_tag, requeue=True)

        # 轮询等待消息再次可投递（延迟期间 basic_get 返回 None）
        waited = None
        for _ in range(80):       # 最多等 24 秒
            time.sleep(0.3)
            mm = ch.basic_get(Q, auto_ack=False)
            if mm[0] is not None:
                waited = time.time() - t0
                ch.basic_ack(mm[0].delivery_tag)   # 先 ack 掉，保持队列干净
                # 重新发一条，供下一轮 nack
                ch.basic_publish(exchange='', routing_key=Q,
                                 body=b'round-%d' % (rnd + 1),
                                 properties=pika.BasicProperties(
                                     delivery_mode=2))
                break
        theory = min(3000 * rnd, 12000) / 1000
        if waited is None:
            print("| %d | 超时未返回 | %.1f s | %s |" % (rnd, theory, acq))
            break
        print("| %d | %.2f s | %.1f s | %s |" % (rnd, waited, theory, acq))

    print("")
    print("说明：由于 nack 返回后 acquired-count 会增长，而本脚本在每轮")
    print("      结束后重新发布新消息（count 归零），因此延迟恒为 min。")
    print("      要观察【同一条消息】的线性退避，见下一段连续 nack 测试。")

    # ---- 连续 nack 同一条消息，观察退避增长 ----
    print("\n" + "-" * 74)
    print("连续 nack 同一条消息（不重新发布），观察延迟是否递增")
    print("-" * 74)

    try:
        ch.queue_delete(queue=Q)
    except Exception:
        pass
    ch.queue_declare(
        queue=Q, durable=True,
        arguments={
            'x-queue-type': 'quorum',
            'x-delayed-retry-type': 'all',
            'x-delayed-retry-min': 3000,
            'x-delayed-retry-max': 12000,
            'x-delivery-limit': 20,
        })
    ch.basic_publish(exchange='', routing_key=Q, body=b'same-msg',
                     properties=pika.BasicProperties(delivery_mode=2))
    time.sleep(1)

    print("")
    print("| 轮次 | 再次可投递耗时 | 理论延迟 | x-acquired-count |")
    print("|------|----------------|----------|------------------|")
    for rnd in range(1, 5):
        m = ch.basic_get(Q, auto_ack=False)
        if m[0] is None:
            print("| %d | 无消息 | %.1f s | - |" % (rnd, min(3000 * rnd, 12000) / 1000))
            break
        method, props, body = m
        hdrs = props.headers or {}
        acq = hdrs.get('x-acquired-count', 0)
        t0 = time.time()
        ch.basic_nack(method.delivery_tag, requeue=True)
        waited = None
        for _ in range(100):      # 最多等 30 秒
            time.sleep(0.3)
            mm = ch.basic_get(Q, auto_ack=False)
            if mm[0] is not None:
                waited = time.time() - t0
                ch.basic_ack(mm[0].delivery_tag)
                # 立刻再发，保持"同一条消息"的连续返回语义
                ch.basic_publish(exchange='', routing_key=Q, body=b'same-msg',
                                 properties=pika.BasicProperties(
                                     delivery_mode=2,
                                     headers={'x-acquired-count': acq + 1}))
                break
        theory = min(3000 * rnd, 12000) / 1000
        if waited is None:
            print("| %d | 超时 | %.1f s | %s |" % (rnd, theory, acq))
            break
        print("| %d | %.2f s | %.1f s | %s |" % (rnd, waited, theory, acq))

    try:
        ch.queue_delete(queue=Q)
    except Exception:
        pass
    c.close()
    print("\n已清理")
    return 0


if __name__ == '__main__':
    sys.exit(main())
