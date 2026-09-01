#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 10 实验 7：延迟退避的精确测量（修正等待窗口）
==================================================
l10-trace-message.py 已证明：消息【从未消失】（total 恒为 1），
之前"第 2 轮无消息"是我的轮询窗口太短、在消息返回前就放弃导致的误报。

同时观测到：
  - x-acquired-count 确实在增长：0 → 1 → 2
  - 延迟期间 messages_ready = 0（消息不可投递），返回后变回 1

本实验用【细粒度轮询 + 精确计时】，测准每轮的延迟时长，
验证 delay = min(min_delay × delivery_count, max_delay) 是否成立。

关键改进：
  1. 轮询间隔 0.2 秒（原 0.3 秒），减少测量误差
  2. 等待窗口 90 秒（原 60 秒），避免误判"消息消失"
  3. 以 HTTP API 的 messages_ready 从 0 变 1 为【返回】信号
  4. 区分 nack 与 reject
"""
import json
import subprocess
import sys
import time

import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')
Q = 'l10.backoff'
API = 'http://localhost:15672/api/queues/%2F/' + Q


def api():
    r = subprocess.run(
        ['curl', '-s', '-u', 'learn:learn123', API],
        capture_output=True, text=True, timeout=30)
    try:
        d = json.loads(r.stdout)
        return d if isinstance(d, dict) else None
    except Exception:
        return None


def ready():
    d = api()
    return d.get('messages_ready', 0) if d else None


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
    ch.basic_publish(exchange='', routing_key=Q, body=b'backoff-probe',
                     properties=pika.BasicProperties(delivery_mode=2))
    time.sleep(1.5)

    rows = []
    for rnd in range(1, rounds + 1):
        # 等到消息 ready
        t_wait = 0
        while ready() != 1 and t_wait < 90:
            time.sleep(0.2)
            t_wait += 0.2
        if ready() != 1:
            rows.append((rnd, None, None))
            break

        m = ch.basic_get(Q, auto_ack=False)
        if m[0] is None:
            rows.append((rnd, None, None))
            break
        method, props, body = m
        hdrs = props.headers or {}
        acq = hdrs.get('x-acquired-count')

        t0 = time.time()
        if mode == 'nack':
            ch.basic_nack(method.delivery_tag, requeue=True)
        else:
            ch.basic_reject(method.delivery_tag, requeue=True)

        # 细粒度轮询，等 messages_ready 从 0 变回 1
        waited = None
        elapsed = 0
        while elapsed < 90:
            time.sleep(0.2)
            elapsed += 0.2
            if ready() == 1:
                waited = time.time() - t0
                break
        rows.append((rnd, waited, acq))

        # 记得把当前这条 ack 掉？不。保持它在队列里，下轮继续取。
        # 注意：basic_get 已经把它变成 unacked，但它 requeue 后回到 ready

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
    print("| 轮次 | 实测延迟 | 理论延迟(min×n) | x-acquired-count |")
    print("|------|----------|------------------|------------------|")
    for rnd, waited, acq in rows:
        theory_ms = min(rmin * rnd, rmax)
        if waited is None:
            print("| %d | 超时/无消息 | %.1f s | %s |" % (rnd, theory_ms / 1000, acq))
        else:
            print("| %d | %.2f s | %.1f s | %s |" % (rnd, waited, theory_ms / 1000, acq))


def main():
    print("=" * 74)
    print("课 10 实验 7：延迟退避精确测量（min=3000ms, max=12000ms）")
    print("=" * 74)
    print("环境：RabbitMQ 4.3.5 / pika %s" % pika.__version__)
    print("方法：以 HTTP API 的 messages_ready 0→1 作为返回信号，0.2s 轮询")

    rmin, rmax = 3000, 12000
    nack_rows = run('nack', rounds=5, rmin=rmin, rmax=rmax)
    show("【NACK】basic_nack(requeue=True)", nack_rows, rmin, rmax)

    rej_rows = run('reject', rounds=5, rmin=rmin, rmax=rmax)
    show("【REJECT】basic_reject(requeue=True)", rej_rows, rmin, rmax)

    print("\n" + "=" * 74)
    print("判定")
    print("=" * 74)
    print("理论：delay = min(min_delay × delivery_count, max_delay)")
    print("      即 3s → 6s → 9s → 12s → 12s（封顶）")
    print("")
    print("⚠️ 注意：公式用的是 delivery_count，而 headers 暴露的是")
    print("   x-acquired-count。按 4.3 文档，nack 只涨 acquired、不涨")
    print("   delivery；reject 两者都涨。若实测两组行为一致，说明本环境")
    print("   下延迟是按 acquired-count 计算，与文档描述不符——如实记录。")

    return 0


if __name__ == '__main__':
    sys.exit(main())
