#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 10 实验 5：连续返回【同一条消息】的延迟退避（严格版）
==========================================================
修正 l10-nack-vs-reject.py 的方法学缺陷：

  之前的做法是"取出 → nack → 等待 → 取出 → ack → 重新发布"，
  这实际上是【新消息】，计数归零，所以永远只有 min 延迟，
  而且 ack+重发 与 basic_get 的时序容易错乱导致"超时"。

正确做法：**取出 → nack(requeue=True) → 等待 → 再次取出（不 ack）→ 再 nack**
  全程不 ack、不重发，让 broker 自己维护这条消息的计数。

本实验严格按此方式，测量：
  - 每次返回后多久再次可投递
  - headers 中 x-acquired-count / x-delivery-count 的实际变化
  - nack 与 reject 的差异

为避免客户端侧超时误判，等待窗口放宽到 60 秒。
"""
import sys
import time

import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')
Q = 'l10.strict'


def conn_of():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=300))


def run(mode, rounds=4, rmin=3000, rmax=12000, qtype='all'):
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
            'x-delayed-retry-type': qtype,
            'x-delayed-retry-min': rmin,
            'x-delayed-retry-max': rmax,
            'x-delivery-limit': 20,
        })
    ch.basic_publish(exchange='', routing_key=Q, body=b'strict-probe',
                     properties=pika.BasicProperties(delivery_mode=2))
    time.sleep(1.5)

    rows = []
    for rnd in range(1, rounds + 1):
        # 取消息（不 ack）
        m = ch.basic_get(Q, auto_ack=False)
        if m[0] is None:
            rows.append((rnd, None, None, None, '队列无消息'))
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

        # 等待它再次可投递（不 ack，取到就立刻再返回）
        waited = None
        for _ in range(200):        # 最多等 60 秒
            time.sleep(0.3)
            mm = ch.basic_get(Q, auto_ack=False)
            if mm[0] is not None:
                waited = time.time() - t0
                break
        if waited is None:
            rows.append((rnd, None, acq, dc, '超时未返回'))
            break
        rows.append((rnd, waited, acq, dc, ''))

    # 清理：把还在队列里的消息拿掉
    try:
        mm = ch.basic_get(Q, auto_ack=False)
        if mm[0] is not None:
            ch.basic_ack(mm[0].delivery_tag)
    except Exception:
        pass
    try:
        ch.queue_delete(queue=Q)
    except Exception:
        pass
    c.close()
    return rows


def show(title, rows, rmin, rmax):
    print("\n" + "-" * 74)
    print(title)
    print("-" * 74)
    print("")
    print("| 轮次 | 再次可投递耗时 | 理论延迟 | x-acquired-count | x-delivery-count |")
    print("|------|----------------|----------|------------------|------------------|")
    for rnd, waited, acq, dc, note in rows:
        theory = min(rmin * rnd, rmax) / 1000
        if waited is None:
            print("| %d | %s | %.1f s | %s | %s |" % (
                rnd, note or '超时', theory, acq, dc))
        else:
            print("| %d | %.2f s | %.1f s | %s | %s |" % (
                rnd, waited, theory, acq, dc))


def main():
    print("=" * 74)
    print("课 10 实验 5：连续返回同一条消息的延迟退避（严格版）")
    print("=" * 74)
    print("配置：type=all, min=3000ms, max=12000ms, delivery-limit=20")
    print("环境：RabbitMQ 4.3.5 / pika %s" % pika.__version__)

    rmin, rmax = 3000, 12000
    nack_rows = run('nack', rounds=4, rmin=rmin, rmax=rmax)
    show("【NACK】basic_nack(requeue=True) 连续返回", nack_rows, rmin, rmax)

    rej_rows = run('reject', rounds=4, rmin=rmin, rmax=rmax)
    show("【REJECT】basic_reject(requeue=True) 连续返回", rej_rows, rmin, rmax)

    print("\n" + "=" * 74)
    print("结论判定")
    print("=" * 74)
    print("理论公式：delay = min(min_delay × delivery_count, max_delay)")
    print("")
    print("若 nack 组耗时恒为 min → 说明 nack 不增加 delivery-count")
    print("若 reject 组耗时递增 → 说明 reject 才让 delivery-count 增长")
    print("")
    print("⚠️ 若两组都恒定在 min，说明本环境（4.3.5）下该特性行为与")
    print("   文档描述存在差异，如实记录，不强行套用文档结论。")

    return 0


if __name__ == '__main__':
    sys.exit(main())
