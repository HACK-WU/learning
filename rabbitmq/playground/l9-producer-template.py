#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 9 实验 6：生产者三件套（confirm + mandatory + persistent）实测
==================================================================
目的：验证"三件套"各自到底防住了什么，缺一件会怎样。

三件套各自的职责（这是本课要讲清的核心）：
  1. confirm（发布确认）→ 防"消息没到 broker"
     开启 confirm_delivery 后，每条 publish 等 broker 回 ack
  2. mandatory + return 回调 → 防"消息到了 broker 但没进任何队列"
     不可路由时 broker 把消息退回，客户端必须注册回调接住
  3. persistent（delivery_mode=2）→ 防"消息进了队列但重启后没了"
     注意：它不保证 confirm 前已落盘（课 7 已证 classic 的 fsync 窗口）

⚠️ 已知坑（课 4 实测）：pika 的 return 回调【不在 publish 返回时立即触发】，
   需等下一次网络往返。这是很多"mandatory 没生效"误判的根因。

实验内容：
  A. 三件套齐全：正常路由 → 全部确认
  B. 三件套齐全：路由不到 → mandatory 触发退回，能拿到回退消息
  C. 不开 confirm：publish 后崩溃，无法知道消息是否到达
  D. 性能代价：confirm 开启前后对比（呼应课 6 结论）

运行：python3 l9-producer-template.py
"""
import sys
import time

import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')
OK_Q = 'l9.prod.ok'
DL_Q = 'l9.prod.dlx'


def conn_of(heartbeat=600):
    return pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=CRED, heartbeat=heartbeat,
        blocked_connection_timeout=300))


def reset():
    c = conn_of()
    ch = c.channel()
    for q in (OK_Q, DL_Q):
        try:
            ch.queue_delete(queue=q)
        except Exception:
            pass
    ch.queue_declare(queue=OK_Q, durable=True)
    ch.queue_declare(queue=DL_Q, durable=True)
    c.close()


def depth(queue):
    c = conn_of()
    ch = c.channel()
    q = ch.queue_declare(queue=queue, durable=True, passive=True)
    n = q.method.message_count
    c.close()
    return n


def scenario_a():
    """A：三件套齐全，正常路由"""
    c = conn_of()
    ch = c.channel()
    ch.confirm_delivery()                 # ① confirm
    returned = []
    ch.add_on_return_callback(
        lambda ch_, method, props, body: returned.append(body.decode()))

    ok = True
    try:
        ch.basic_publish(
            exchange='', routing_key=OK_Q, body=b'A-normal-msg',
            properties=pika.BasicProperties(delivery_mode=2),   # ③ persistent
            mandatory=True)                                     # ② mandatory
    except pika.exceptions.UnroutableError as e:
        ok = False
    c.close()
    return ok, returned, depth(OK_Q)


def scenario_b():
    """B：三件套齐全，但路由不到（不存在的 routing key）"""
    c = conn_of()
    ch = c.channel()
    ch.confirm_delivery()
    returned = []
    ch.add_on_return_callback(
        lambda ch_, method, props, body: returned.append(
            (method.reply_code, method.reply_text, body.decode())))

    raised = None
    try:
        ch.basic_publish(
            exchange='', routing_key='l9.no.such.queue.at.all',
            body=b'B-unroutable-msg',
            properties=pika.BasicProperties(delivery_mode=2),
            mandatory=True)
    except pika.exceptions.UnroutableError as e:
        raised = '%s' % type(e).__name__
    # 课 4 已证：return 回调需下次网络往返才触发，这里补一次交互
    try:
        ch.queue_declare(queue=OK_Q, durable=True, passive=True)
    except Exception:
        pass
    time.sleep(0.3)
    c.close()
    return raised, returned


def scenario_c():
    """C：不开 confirm，publish 后立即返回（无法确认是否到达）"""
    c = conn_of()
    ch = c.channel()
    t0 = time.perf_counter()
    for i in range(100):
        ch.basic_publish(exchange='', routing_key=OK_Q,
                         body=('C-%d' % i).encode(),
                         properties=pika.BasicProperties(delivery_mode=2))
    t1 = time.perf_counter()
    c.close()
    return (t1 - t0) * 1000


def scenario_d():
    """D：开 confirm 后的耗时（同样 100 条）"""
    c = conn_of()
    ch = c.channel()
    ch.confirm_delivery()
    t0 = time.perf_counter()
    for i in range(100):
        ch.basic_publish(exchange='', routing_key=OK_Q,
                         body=('D-%d' % i).encode(),
                         properties=pika.BasicProperties(delivery_mode=2))
    t1 = time.perf_counter()
    c.close()
    return (t1 - t0) * 1000


def main():
    print("=" * 74)
    print("课 9 实验 6：生产者三件套实测（pika %s）" % pika.__version__)
    print("=" * 74)

    reset()

    print("\n【A】三件套齐全 + 正常路由")
    ok, returned, d = scenario_a()
    print("  publish 未抛异常：%s" % ok)
    print("  触发退回的消息数：%d（应为 0）" % len(returned))
    print("  队列 %s 深度：%d（应为 1）" % (OK_Q, d))

    print("\n【B】三件套齐全 + 路由不到（routing_key 不存在）")
    raised, returned = scenario_b()
    print("  抛出的异常：%s" % raised)
    print("  退回回调收到的消息：%d 条" % len(returned))
    for r in returned:
        print("    reply_code=%s reply_text=%s body=%s" % r)
    print("  → 结论：mandatory 生效时能【接住】不可路由消息，")
    print("     否则这些消息会被【静默丢弃】，发布方毫无察觉")

    print("\n【C vs D】confirm 的性能代价（各 100 条持久化消息）")
    tc = scenario_c()
    td = scenario_d()
    print("")
    print("| 模式 | 100 条耗时 | 单条平均 |")
    print("|------|-----------|----------|")
    print("| 不开 confirm | %.1f ms | %.3f ms |" % (tc, tc / 100))
    print("| 开启 confirm | %.1f ms | %.3f ms |" % (td, td / 100))
    print("")
    print("  倍率：confirm 约为无确认的 %.1f 倍耗时" % (td / tc if tc else 0))
    print("  （呼应课 6 结论：pika 的 confirm 是逐条同步等待 RTT，")
    print("    慢的是【同步适配器的用法】，不是协议本身）")

    # 清理
    c = conn_of()
    ch = c.channel()
    for q in (OK_Q, DL_Q):
        try:
            ch.queue_delete(queue=q)
        except Exception:
            pass
    c.close()
    print("\n已清理临时队列")
    return 0


if __name__ == '__main__':
    sys.exit(main())
