#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 10 实验 6：追踪延迟重试中"消失"的消息
==========================================
现象：l10-retry-strict.py 中，第 1 次 nack 后消息 3 秒返回，
      但第 2 次 nack 后消息【再也取不到】。

可能去向：
  1. 进了死信队列（delivery-limit 触发）—— 但 limit=20，不该这么快
  2. 仍在延迟中，basic_get 取不到（延迟消息不可投递）
  3. 被丢弃（overflow / 无 DLX 时的毒消息处理）
  4. 卡在 "unacked" 未确认状态

本实验用 HTTP API 精确查看队列的四个计数：
  messages / messages_ready / messages_unacknowledged / messages_delayed
（4.3 的 Management API 对延迟队列可能提供 messages_delayed 字段）

方法：每一步操作后打印完整计数，定位消息究竟在哪。
"""
import json
import subprocess
import sys
import time

import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')
Q = 'l10.trace'
API_BASE = 'http://localhost:15672/api/queues/%2F/'


def api(path=''):
    r = subprocess.run(
        ['curl', '-s', '-u', 'learn:learn123', API_BASE + Q + path],
        capture_output=True, text=True, timeout=30)
    try:
        return json.loads(r.stdout)
    except Exception:
        return None


def counters(tag):
    d = api()
    if not d or not isinstance(d, dict):
        print("  [%s] 读取失败" % tag)
        return
    keys = ['messages', 'messages_ready', 'messages_unacknowledged']
    # 4.3 可能提供延迟计数
    for k in ('messages_delayed', 'messages_delayed_raft',
              'delayed_message_count'):
        if k in d:
            keys.append(k)
    vals = {k: d.get(k) for k in keys}
    print("  [%-22s] %s" % (tag, vals))


def conn_of():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=300))


def main():
    print("=" * 74)
    print("课 10 实验 6：追踪延迟重试中消失的消息")
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
    ch.basic_publish(exchange='', routing_key=Q, body=b'trace-me',
                     properties=pika.BasicProperties(delivery_mode=2))
    time.sleep(1)
    counters('发布后')

    for rnd in range(1, 4):
        print("\n--- 第 %d 轮 ---" % rnd)
        m = ch.basic_get(Q, auto_ack=False)
        if m[0] is None:
            print("  basic_get 返回 None")
            counters('basic_get 为 None')
            # 等 10 秒再看
            time.sleep(10)
            counters('等待 10s 后')
            m = ch.basic_get(Q, auto_ack=False)
            if m[0] is None:
                print("  等待后仍无消息 → 消息已离开队列")
                break
        method, props, body = m
        hdrs = props.headers or {}
        print("  取到消息 headers=%s" % (hdrs if hdrs else '（无）'))
        counters('取出后（unacked）')

        t0 = time.time()
        ch.basic_nack(method.delivery_tag, requeue=True)
        print("  已 nack(requeue=True)")
        counters('nack 后立刻')

        # 每 2 秒看一次计数，持续 16 秒
        for i in range(8):
            time.sleep(2)
            d = api()
            if d and isinstance(d, dict):
                print("    +%.0fs: ready=%s unacked=%s total=%s" % (
                    time.time() - t0, d.get('messages_ready'),
                    d.get('messages_unacknowledged'), d.get('messages')))

    print("\n" + "=" * 74)
    print("诊断结论")
    print("=" * 74)
    print("观察点：")
    print("  1. 若 nack 后 ready=0 且 unacked=0 且 total=0 → 消息已离开队列")
    print("  2. 若 total 保持 1 但 ready=0 → 消息在延迟状态（不可投递）")
    print("  3. 若 total 归 0 → 被死信/丢弃，需检查 delivery-limit 与 DLX")

    try:
        ch.queue_delete(queue=Q)
    except Exception:
        pass
    c.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
