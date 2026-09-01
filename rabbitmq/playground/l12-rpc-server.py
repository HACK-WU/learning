#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 12 实验：RPC 服务端（独立进程，生成器式 consume）

为什么用生成器式 channel.consume() 而不是回调式 basic_consume()？
  【实测发现】在本环境（WSL/Windows 宿主 + docker 网络 + pika 1.4.4）：
    - 回调式 basic_consume()：broker 侧 consumers 恒为 0，注册不生效
    - 生成器式 consume()：broker 侧 consumers = 1，注册成功
  故采用生成器式。

为什么用独立进程而不是线程？
  pika 的 BlockingConnection 非线程安全。实测同进程内
  服务端线程 + 客户端线程同时推进 I/O 会报：
    StreamLostError: Stream connection lost: IndexError('pop from an empty deque')
  拆成两个进程 = 生产环境真实形态，也彻底避开该问题。

用法：
    python3 l12-rpc-server.py &    # 先起
    python3 l12-rpc-client2.py     # 后跑
"""
import sys
import time

import pika

PORT = 5681
CRED = pika.PlainCredentials('learn', 'learn123')
RPC_Q = 'l12.rpc.cmp'


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

    # 生成器式：迭代它就会真正注册消费者
    gen = ch.consume(RPC_Q, inactivity_timeout=120, auto_ack=False)
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
            print("  [服务端] fib(%d)=%d → %s" % (n, r, props.reply_to),
                  flush=True)
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
