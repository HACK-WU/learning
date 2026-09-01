#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""诊断 RPC：确认服务端消费者是否注册、请求是否入队、回复发往何处。"""
import json
import subprocess
import sys
import threading
import time
import uuid

import pika

PORT = 5681
UI = 15681
CRED = pika.PlainCredentials('learn', 'learn123')
RPC_Q = 'l12.rpc.diag'
REPLY_Q = 'amq.rabbitmq.reply-to'


def conn():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost', port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=30, socket_timeout=30))


def api(path):
    r = subprocess.run(['curl', '-s', '-u', 'learn:learn123',
                        'http://localhost:%d/api/%s' % (UI, path)],
                       capture_output=True, text=True, timeout=20)
    try:
        return json.loads(r.stdout)
    except Exception:
        return None


def main():
    print("=" * 70)
    print("RPC 诊断")
    print("=" * 70)

    c = conn()
    ch = c.channel()
    try:
        ch.queue_delete(queue=RPC_Q)
    except Exception:
        pass
    time.sleep(1)
    ch.queue_declare(queue=RPC_Q, durable=True,
                     arguments={'x-queue-type': 'quorum'})
    time.sleep(2)

    # 服务端：独立连接 + consume 生成器
    # 服务端：独立连接 + basic_consume 回调（立即注册，非惰性生成器）
    served = []
    sconn = conn()
    sch = sconn.channel()
    sch.basic_qos(prefetch_count=1)

    def on_request(chx, method, props, body):
        n = int(body)
        chx.basic_publish(exchange='', routing_key=props.reply_to,
                          body=str(n * 2).encode(),
                          properties=pika.BasicProperties(
                              correlation_id=props.correlation_id))
        chx.basic_ack(method.delivery_tag)
        served.append(n)

    sch.basic_consume(queue=RPC_Q, on_message_callback=on_request,
                      auto_ack=False)
    print("  [服务端] basic_consume 已注册，等待请求...")

    # 用独立线程驱动服务端的 I/O 循环（避免与客户端的 process_data_events 抢）
    stop = threading.Event()

    def drive_server():
        while not stop.is_set():
            try:
                sconn.process_data_events(time_limit=0.3)
            except Exception:
                break

    t = threading.Thread(target=drive_server)
    t.start()
    time.sleep(2)

    # 检查消费者数
    d = api('queues/%%2F/%s' % RPC_Q)
    print("\n  队列 %s：messages=%s, consumers=%s" % (
        RPC_Q, (d or {}).get('messages'), (d or {}).get('consumers')))

    # 客户端：同一连接新 channel 注册响应
    replies = {}
    rch = c.channel()

    def on_reply(chx, method, props, body):
        replies[props.correlation_id] = body.decode()

    rch.basic_consume(queue=REPLY_Q, on_message_callback=on_reply, auto_ack=True)
    time.sleep(1)
    print("  [客户端] 已注册 %s 的消费者" % REPLY_Q)

    cid = str(uuid.uuid4())
    ch.basic_publish(exchange='', routing_key=RPC_Q, body=b'21',
                     properties=pika.BasicProperties(
                         reply_to=REPLY_Q, correlation_id=cid))
    print("  [客户端] 已发请求 n=21, cid=%s" % cid[:8])

    t0 = time.time()
    while not replies and time.time() - t0 < 15:
        c.process_data_events(time_limit=0.5)

    print("\n  服务端处理：%s" % served)
    print("  客户端收到：%s" % (replies if replies else "无 ❌"))
    print("  耗时：%.2fs" % (time.time() - t0))

    stop.set()
    t.join(timeout=5)
    try:
        ch.queue_delete(queue=RPC_Q)
    except Exception:
        pass
    try:
        c.close()
    except Exception:
        pass
    return 0


if __name__ == '__main__':
    sys.exit(main())
