#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 12 实验：Direct Reply-To 的服务端（独立进程，生成器式 consume）

与 l12-rpc-server.py 唯一的区别是队列名，避免与普通回调队列实验互相干扰。

关键点：服务端不需要知道客户端用的是哪种 reply_to——它只是把响应
发到 props.reply_to 指定的路由键。
  - 普通回调队列：reply_to = amq.gen-xxxx（真实队列）
  - Direct Reply-To：broker 会把 reply_to 改写成
    amq.rabbitmq.reply-to.<opaque-suffix>，服务端照发即可
"""
import sys

import pika

PORT = 5681
CRED = pika.PlainCredentials('learn', 'learn123')
RPC_Q = 'l12.rpc.drt'


def fib(n):
    return n if n < 2 else fib(n - 1) + fib(n - 2)


def main():
    conn = pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost', port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=120, socket_timeout=120))
    ch = conn.channel()
    ch.queue_declare(queue=RPC_Q, durable=True,
                     arguments={'x-queue-type': 'quorum'})
    ch.basic_qos(prefetch_count=1)

    gen = ch.consume(RPC_Q, inactivity_timeout=90, auto_ack=False)
    print("  [服务端] 已就绪，等待请求（queue=%s）" % RPC_Q, flush=True)

    try:
        for m in gen:
            if m[0] is None:
                continue
            method, props, body = m[0], m[1], m[2]
            n = int(body)
            r = fib(n)
            ch.basic_publish(exchange='', routing_key=props.reply_to,
                             body=str(r).encode(),
                             properties=pika.BasicProperties(
                                 correlation_id=props.correlation_id))
            ch.basic_ack(method.delivery_tag)
            print("  [服务端] fib(%d)=%d → reply_to=%s" % (
                n, r, props.reply_to), flush=True)
    except KeyboardInterrupt:
        print("\n  [服务端] 退出", flush=True)
    except Exception as e:
        print("  [服务端] 异常：%s" % str(e)[:90], flush=True)
    try:
        conn.close()
    except Exception:
        pass
    return 0


if __name__ == '__main__':
    sys.exit(main())
