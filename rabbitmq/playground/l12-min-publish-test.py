#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
最小复现（第二版）：basic_publish → 默认交换机 → quorum 队列

改用 rabbitmqctl 读队列深度，绕开 Management API 的 URL 转义坑。
（在 API 路径上已耗掉太多时间，主目标不能跑偏：
  确认 basic_publish 到默认交换机能否正常入队。）
"""
import subprocess
import sys
import time

import pika

PORT = 5681
CRED = pika.PlainCredentials('learn', 'learn123')
Q = 'l12.min.q'


def depth():
    """用 rabbitmqctl 读指定队列的深度"""
    r = subprocess.run(
        ['docker', 'exec', 'rmq1', 'rabbitmqctl', 'list_queues',
         'name', 'messages', 'consumers', '--quiet'],
        capture_output=True, text=True, timeout=90)
    out = r.stdout or ''
    for ln in out.splitlines()[1:]:
        parts = ln.split('\t')
        if len(parts) >= 3 and parts[0].strip() == Q:
            return parts[1].strip(), parts[2].strip()
    return None, None


def main():
    print("=" * 66)
    print("最小复现（第二版）：basic_publish → 默认交换机 → quorum")
    print("=" * 66)

    c = pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost', port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=60, socket_timeout=60))
    ch = c.channel()
    try:
        ch.queue_delete(queue=Q)
    except Exception:
        pass
    time.sleep(1)
    ch.queue_declare(queue=Q, durable=True,
                     arguments={'x-queue-type': 'quorum'})
    time.sleep(2)
    d, cc = depth()
    print("\n  队列已建：messages=%s consumers=%s" % (d, cc))

    print("\n【场景 1】不开 confirm，发 1 条")
    ch.basic_publish(exchange='', routing_key=Q, body=b'no-confirm')
    c.process_data_events(time_limit=1.0)
    time.sleep(1)
    d, _ = depth()
    print("  messages = %s" % d)

    print("\n【场景 2】开启 confirm_delivery，再发 1 条")
    ch.confirm_delivery()
    ch.basic_publish(exchange='', routing_key=Q, body=b'with-confirm',
                     properties=pika.BasicProperties(delivery_mode=2))
    time.sleep(1)
    d, _ = depth()
    print("  messages = %s" % d)

    print("\n【场景 3】带 reply_to 发送（无响应消费者）——预期失败")
    ch2 = c.channel()
    try:
        ch2.basic_publish(exchange='', routing_key=Q, body=b'with-replyto',
                          properties=pika.BasicProperties(
                              reply_to='amq.rabbitmq.reply-to',
                              correlation_id='x'))
        time.sleep(1)
        print("  未报错（意外）")
    except Exception as e:
        print("  ❌ %s" % str(e).split('\n')[0][:80])

    print("\n【取回消息】")
    got = []
    for _ in range(20):
        m = ch.basic_get(Q, auto_ack=True)
        if m[0] is None:
            break
        got.append(m[2].decode())
    print("  取到 %d 条：%s" % (len(got), got))

    try:
        ch.queue_delete(queue=Q)
    except Exception:
        pass
    c.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
