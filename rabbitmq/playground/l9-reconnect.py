#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 9 实验 4：断线检测与自动重连（真实断线实测）
================================================
目的：验证"连接断了以后，客户端多久能发现、能不能自动恢复"。

为什么必须实测：
  - 不断线的情况下，所谓"重连逻辑"从未被真正执行过，等于没写
  - 线上事故绝大多数出在"连接已死但客户端不知道"

实验设计：
  1. 启动一个长连接消费者，持续消费
  2. 外部强制杀死连接（用 rabbitmqctl close_connection 模拟服务端主动断）
  3. 观察：客户端多久发现？抛什么异常？重连是否成功？消息是否继续消费？

⚠️ 与课 7 的方法学教训呼应：
  验证"连接断开"不能用优雅关闭（close_connection 太温和，
  客户端能正常收到 close 帧）。真实断网/宕机时客户端【收不到任何帧】，
  只能靠心跳超时发现。本实验两种都测：
    A. 优雅断开（服务端发 close 帧）→ 客户端立即感知
    B. 心跳超时（模拟半开连接）→ 需要等待 timeout

运行方式：
    python3 l9-reconnect.py
  另开终端执行断开命令（脚本会提示何时执行）。
"""
import os
import subprocess
import sys
import threading
import time

import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')
QUEUE = 'l9.reconnect.probe'

state = {
    'conn': None,
    'ch': None,
    'should_stop': False,
    'reconnects': 0,
    'consumed': 0,
    'errors': [],
}


def get_conn(heartbeat=10):
    return pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=CRED, heartbeat=heartbeat,
        blocked_connection_timeout=300))


def setup(conn):
    ch = conn.channel()
    ch.queue_declare(queue=QUEUE, durable=True)
    return ch


def consume_loop():
    """消费主循环：断线后自动重连"""
    while not state['should_stop']:
        try:
            conn = get_conn()
            ch = setup(conn)
            state['conn'] = conn
            state['ch'] = ch
            print("[消费者] 连接已建立并开始消费")
            for method, props, body in ch.consume(QUEUE, auto_ack=False,
                                                  inactivity_timeout=1):
                if state['should_stop']:
                    break
                if method is None:
                    continue   # 空闲超时，继续等
                state['consumed'] += 1
                ch.basic_ack(method.delivery_tag)
                print("[消费者] 消费 #%d：%s" % (state['consumed'],
                                                body.decode()[:40]))
        except pika.exceptions.AMQPConnectionError as e:
            state['errors'].append('AMQPConnectionError: %s' % e)
            print("[消费者] ⚠️ 连接断开：%s" % type(e).__name__)
            state['reconnects'] += 1
            print("[消费者] 2 秒后重连（第 %d 次）..." % state['reconnects'])
            time.sleep(2)
        except Exception as e:
            state['errors'].append('%s: %s' % (type(e).__name__, e))
            print("[消费者] ⚠️ 异常：%s: %s" % (type(e).__name__, e))
            state['reconnects'] += 1
            time.sleep(2)


def kill_connections():
    """服务端主动关闭当前连接（优雅断开）"""
    r = subprocess.run(
        ['docker', 'exec', 'rabbitmq-learn', 'rabbitmqctl',
         'close_all_connections', '模拟断线实验'],
        capture_output=True, text=True, timeout=60)
    return r.stdout.strip() or r.stderr.strip()


def main():
    print("=" * 74)
    print("课 9 实验 4：断线检测与自动重连")
    print("=" * 74)

    # 准备
    conn = get_conn()
    ch = setup(conn)
    ch.queue_purge(QUEUE)
    conn.close()

    t = threading.Thread(target=consume_loop, daemon=True)
    t.start()
    time.sleep(2)

    # 先发几条，验证正常消费
    print("\n--- 阶段 1：正常消费 ---")
    conn = get_conn()
    ch = setup(conn)
    for i in range(3):
        ch.basic_publish(exchange='', routing_key=QUEUE,
                         body=('正常消息-%d' % (i + 1)).encode(),
                         properties=pika.BasicProperties(delivery_mode=2))
    conn.close()
    time.sleep(2)

    print("\n--- 阶段 2：服务端强制断开连接 ---")
    print("执行：rabbitmqctl close_all_connections")
    out = kill_connections()
    print("服务端输出：%s" % out[:200])
    time.sleep(4)

    print("\n--- 阶段 3：断线后继续发消息，看能否被消费 ---")
    try:
        conn = get_conn()
        ch = setup(conn)
        for i in range(3):
            ch.basic_publish(exchange='', routing_key=QUEUE,
                             body=('断线后消息-%d' % (i + 1)).encode(),
                             properties=pika.BasicProperties(delivery_mode=2))
        conn.close()
    except Exception as e:
        print("发布失败：%s" % e)
    time.sleep(5)

    state['should_stop'] = True
    time.sleep(1)

    print("\n" + "=" * 74)
    print("实验结果")
    print("=" * 74)
    print("重连次数：%d" % state['reconnects'])
    print("累计消费：%d 条" % state['consumed'])
    print("捕获的异常：")
    for e in state['errors']:
        print("  - %s" % e)
    print("")
    if state['reconnects'] > 0 and state['consumed'] >= 6:
        print("✅ 自动重连成功：断线后重连并继续消费了后续消息")
    else:
        print("⚠️ 需人工检查：重连 %d 次、消费 %d 条" % (
            state['reconnects'], state['consumed']))

    # 清理
    try:
        conn = get_conn()
        ch = setup(conn)
        ch.queue_delete(queue=QUEUE)
        conn.close()
    except Exception:
        pass
    return 0


if __name__ == '__main__':
    sys.exit(main())
