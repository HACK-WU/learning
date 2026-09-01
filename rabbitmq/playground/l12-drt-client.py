#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 12 实验：Direct Reply-To 客户端（单连接 + 单信道 + 先注册后发布）

【为什么这次能跑通——三个此前踩过的坑】

坑 1：官方要求【同一连接 + 同一信道】
  官方文档原文（AMQP 0.9.1 Caveats and Limitations）：
    "The RPC client must use the same connection and channel for both
     consuming from amq.rabbitmq.reply-to and for publishing the request
     message."
  此前用「发布用一个信道、收响应用另一个信道」→ broker 报
    (406, 'PRECONDITION_FAILED - fast reply consumer does not exist')

坑 2：生成器式 consume() 是【惰性】的
  pika 的 channel.consume() 返回生成器，只有第一次迭代（next）时才真正
  发出 basic.consume 帧注册消费者。此前「先 publish 再 consume」= 注册晚于
  发布 → 同样 406。
  修法（pika 官方维护者 Luke Bakken 给出的写法）：
    next(channel.consume('amq.rabbitmq.reply-to', auto_ack=True,
                         inactivity_timeout=0.1))   # 预热注册
    然后再 publish

坑 3：pika BlockingConnection 非线程安全
  此前同进程内「服务端线程 + 客户端线程」同时推进 I/O →
    StreamLostError: IndexError('pop from an empty deque')
  修法：服务端拆成独立进程（l12-drt-server.py），客户端保持单线程。

本脚本把三件事合起来：
  单连接 → 单信道 → 先 next() 预热注册消费者 → 再 publish → 再收响应
"""
import subprocess
import sys
import time
import uuid

import pika

PORT = 5681
CRED = pika.PlainCredentials('learn', 'learn123')
RPC_Q = 'l12.rpc.drt'
PSEUDO = 'amq.rabbitmq.reply-to'


def main():
    print("=" * 72)
    print("课 12 实验：Direct Reply-To 完整往返")
    print("=" * 72)

    # ---- 前置检查：服务端是否已就绪 ----
    r = subprocess.run(
        ['docker', 'exec', 'rmq1', 'rabbitmqctl', 'list_queues',
         'name', 'messages', 'consumers', '--quiet'],
        capture_output=True, text=True, timeout=90)
    consumers = None
    for ln in (r.stdout or '').splitlines()[1:]:
        p = ln.split('\t')
        if len(p) >= 3 and p[0].strip() == RPC_Q:
            consumers = p[2].strip()
    if not consumers or consumers == '0':
        print("\n  ❌ 服务端未就绪（consumers=%s），请先运行：" % consumers)
        print("     python3 l12-drt-server.py &")
        return 1
    print("\n  服务端已就绪：%s consumers=%s" % (RPC_Q, consumers))

    conn = pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost', port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=120, socket_timeout=120))
    # 关键：整个 RPC 只用一个信道
    ch = conn.channel()

    # ---- 第 1 步：预热注册伪队列消费者（必须在 publish 之前）----
    # next() 触发 pika 真正发出 basic.consume 帧
    try:
        next(ch.consume(PSEUDO, auto_ack=True, inactivity_timeout=0.1))
    except StopIteration:
        pass
    print("\n  [1] 已注册伪队列消费者（pre-warm next() 完成注册）")
    print("      reply_to = %s" % PSEUDO)

    # 用 broker 视角确认消费者确实存在（伪队列不出现在 list_queues 里，
    # 所以这里看的是本连接的 consumer 数）
    time.sleep(0.3)

    # ---- 第 2 步：在同一信道上发布请求 ----
    expected = {5: 5, 10: 55, 15: 610, 20: 6765}
    corr = {}
    for n in (5, 10, 15, 20):
        cid = str(uuid.uuid4())
        corr[cid] = n
        ch.basic_publish(exchange='', routing_key=RPC_Q,
                         body=str(n).encode(),
                         properties=pika.BasicProperties(
                             reply_to=PSEUDO, correlation_id=cid,
                             delivery_mode=2))
    print("  [2] 已在同一信道发布 4 个请求：fib(5) fib(10) fib(15) fib(20)")

    # ---- 第 3 步：收响应 ----
    collected = {}
    t0 = time.time()
    for m in ch.consume(PSEUDO, inactivity_timeout=15, auto_ack=True):
        if m[0] is None:
            break
        method, props, body = m[0], m[1], m[2]
        collected[props.correlation_id] = body.decode()
        print("      ← 收到响应 cid=%s... body=%s" % (
            str(props.correlation_id)[:8], body.decode()))
        if len(collected) >= 4:
            break
        if time.time() - t0 > 20:
            break
    elapsed = time.time() - t0

    # ---- 结果 ----
    ok = 0
    print("")
    print("  | 请求 | 期望 | 实际响应 |")
    print("  |------|------|----------|")
    for cid, n in corr.items():
        got = collected.get(cid, '（未收到）')
        good = str(got) == str(expected[n])
        if good:
            ok += 1
        print("  | fib(%d) | %d | %s %s |" % (
            n, expected[n], got, "✅" if good else "❌"))
    print("")
    print("  正确 %d/4，耗时 %.2fs" % (ok, elapsed))
    print("")
    if ok == 4:
        print("  ✅ Direct Reply-To 完整往返成功")
    else:
        print("  ❌ Direct Reply-To 往返未成功（%d/4）" % ok)

    try:
        conn.close()
    except Exception:
        pass
    return 0 if ok == 4 else 1


if __name__ == '__main__':
    sys.exit(main())
