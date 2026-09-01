#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 10 实验 8：延迟退避测量（以 basic_get 为准，最终版）
==========================================================
方法学演进（如实记录三次失败）：
  1) l10-retry-multiroound.py：ack + 重发 → 变成新消息，计数归零，测不到退避
  2) l10-retry-strict.py   ：等待窗口 36~60s 但轮询在返回前放弃 → 误报"消息消失"
  3) l10-backoff-measure.py：以 HTTP API 的 messages_ready 0→1 为信号，
                             但 nack 后 requeue 瞬时完成、ready 立刻回到 1，
                             测到的是 0.21s（requeue 耗时），而非延迟

l10-trace-message.py 已证明两件事：
  - 消息从未消失（total 恒为 1）
  - 延迟期间 basic_get 返回 None（不可投递），返回后可取到

因此【最可靠的信号是 basic_get 能否取到消息】，本实验采用之：
    nack → 循环 basic_get 直到取到（不 ack，下轮继续）
    取到的那一刻即为"延迟结束"

⚠️ 一个关键细节：取到消息后若不 ack，它就停留在 unacked；
   直接下一轮 basic_get 会取不到它。所以每轮取到后要
   【再次 nack】把它打回队列 —— 这就是连续返回的正确姿势。
"""
import sys
import time

import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')
Q = 'l10.final'


def conn_of():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=300))


def run(mode, rounds, rmin, rmax):
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
    ch.basic_publish(exchange='', routing_key=Q, body=b'final-probe',
                     properties=pika.BasicProperties(delivery_mode=2))
    time.sleep(1.5)

    rows = []
    # 第 0 轮：先把消息取出来并 nack，启动延迟
    for rnd in range(1, rounds + 1):
        # 阶段 1：等待消息可投递（basic_get 能取到）
        t0 = time.time()
        got = None
        elapsed = 0
        while elapsed < 120:
            m = ch.basic_get(Q, auto_ack=False)
            if m[0] is not None:
                got = m
                break
            time.sleep(0.2)
            elapsed += 0.2
        if got is None:
            rows.append((rnd, None, None, '等待可投递超时'))
            break
        wait_ready = time.time() - t0

        method, props, body = got
        hdrs = props.headers or {}
        acq = hdrs.get('x-acquired-count')

        if rnd == 1:
            # 第 1 轮记录的是"初始可投递"耗时，无延迟意义
            rows.append((rnd, None, acq, '首次取出（无延迟）'))
        else:
            rows.append((rnd, wait_ready, acq, ''))

        # 阶段 2：nack/reject 打回队列，触发下一轮延迟
        t1 = time.time()
        if mode == 'nack':
            ch.basic_nack(method.delivery_tag, requeue=True)
        else:
            ch.basic_reject(method.delivery_tag, requeue=True)

    # 清理
    try:
        m = ch.basic_get(Q, auto_ack=False)
        if m[0] is not None:
            ch.basic_ack(m[0].delivery_tag)
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
    print("| 轮次 | 实测延迟 | 理论延迟 | x-acquired-count | 备注 |")
    print("|------|----------|----------|------------------|------|")
    for r in rows:
        rnd, waited, acq, note = r
        theory = min(rmin * rnd, rmax) / 1000
        if waited is None:
            print("| %d | - | %.1f s | %s | %s |" % (rnd, theory, acq, note))
        else:
            print("| %d | %.2f s | %.1f s | %s | %s |" % (
                rnd, waited, theory, acq, note or ''))


def main():
    print("=" * 74)
    print("课 10 实验 8：延迟退避测量（basic_get 信号，最终版）")
    print("=" * 74)
    print("配置：type=all, min=3000ms, max=12000ms, delivery-limit=20")
    print("环境：RabbitMQ 4.3.5 / pika %s" % pika.__version__)

    rmin, rmax = 3000, 12000
    nack_rows = run('nack', rounds=6, rmin=rmin, rmax=rmax)
    show("【NACK】basic_nack(requeue=True)", nack_rows, rmin, rmax)

    rej_rows = run('reject', rounds=6, rmin=rmin, rmax=rmax)
    show("【REJECT】basic_reject(requeue=True)", rej_rows, rmin, rmax)

    print("\n" + "=" * 74)
    print("判定")
    print("=" * 74)
    print("理论：3s → 6s → 9s → 12s → 12s → 12s")
    print("实测若非此规律，如实记录，不套用文档结论。")

    return 0


if __name__ == '__main__':
    sys.exit(main())
