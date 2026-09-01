#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 12 实验：RPC 客户端（独立进程）

演示 Direct Reply-To（reply_to = 'amq.rabbitmq.reply-to'）：
  - 伪队列【无需声明】、不占 broker 资源
  - 但【绑死连接】——响应只会回到发起请求的这条连接

实测约束（本脚本会验证）：
  1. 无活跃消费者时发布带 reply_to 的消息 → 报 406 fast reply consumer does not exist
  2. 在【另一个连接】上访问伪队列 → 报 404 no queue 'amq.rabbitmq.reply-to'

用法：先另开一个终端跑 l12-rpc-server.py，再跑本脚本。
"""
import json
import subprocess
import sys
import time
import uuid

import pika

PORT = 5681
UI = 15681
CRED = pika.PlainCredentials('learn', 'learn123')
RPC_Q = 'l12.rpc.fib'
REPLY_Q = 'amq.rabbitmq.reply-to'


def conn():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost', port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=60, socket_timeout=60))


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
    print("课 12 实验：RPC 客户端（Direct Reply-To）")
    print("=" * 70)

    # 前置检查：服务端是否已起
    d = api('queues/%%2F/%s' % RPC_Q)
    if not d:
        print("\n  ❌ 队列 %s 不存在" % RPC_Q)
        print("     请先另开终端运行：python3 l12-rpc-server.py")
        return 1
    n_consumers = d.get('consumers') or 0
    print("\n  队列 %s：consumers=%s" % (RPC_Q, n_consumers))
    if n_consumers == 0:
        print("  ⚠️ 服务端未启动，请求会堆积而不被处理")
        print("     请另开终端运行：python3 l12-rpc-server.py")
        return 1

    c = conn()
    ch = c.channel()

    # ---------- 约束 1：无监听时发布 ----------
    # 用【独立 channel】探测——实测该操作会异步返回 406 并关闭 channel，
    # 这正是"必须先有响应消费者"这条约束的实证。
    print("\n【约束 1】无活跃消费者时，发布带 reply_to 的消息")
    probe_ch = c.channel()
    try:
        probe_ch.basic_publish(exchange='', routing_key=RPC_Q, body=b'1',
                               properties=pika.BasicProperties(
                                   reply_to=REPLY_Q))
        c.process_data_events(time_limit=1.0)   # 强制 flush 触发错误
        print("  结果：✅ 未报错")
        print("  ⚠️ 与预期不同：说明 broker 本例未校验（可能已有消费者）")
    except Exception as e:
        print("  结果：❌ %s" % str(e).split('\n')[0][:80])
        print("  → 证实：没有响应消费者时，带 reply_to 的发布会被拒绝")
    try:
        probe_ch.close()
    except Exception:
        pass

    # ---------- 正式 RPC ----------
    print("\n【正式调用】先注册响应消费者，再发请求")
    responses = {}
    corr_ids = {}

    ch = c.channel()            # 请求用新 channel（探测可能已污染旧的）
    reply_ch = c.channel()      # 同一连接，新 channel

    def on_reply(chx, method, props, body):
        responses[props.correlation_id] = body.decode()

    reply_ch.basic_consume(queue=REPLY_Q, on_message_callback=on_reply,
                           auto_ack=True)
    time.sleep(1)

    for n in (5, 10, 15, 20):
        cid = str(uuid.uuid4())
        corr_ids[cid] = n
        ch.basic_publish(exchange='', routing_key=RPC_Q,
                         body=str(n).encode(),
                         properties=pika.BasicProperties(
                             reply_to=REPLY_Q, correlation_id=cid,
                             delivery_mode=2))
    print("  已发送 4 个请求：fib(5) fib(10) fib(15) fib(20)")

    t0 = time.time()
    while len(responses) < 4 and time.time() - t0 < 30:
        c.process_data_events(time_limit=0.5)
    elapsed = time.time() - t0

    print("")
    print("  | 请求 | 期望 | 实际响应 | 耗时 |")
    print("  |------|------|----------|------|")
    expected = {5: 5, 10: 55, 15: 610, 20: 6765}
    ok = 0
    for cid, n in corr_ids.items():
        got = responses.get(cid, '（未收到）')
        exp = expected[n]
        match = str(got) == str(exp)
        if match:
            ok += 1
        print("  | fib(%d) | %d | %s %s | — |" % (
            n, exp, got, "✅" if match else "❌"))
    print("")
    print("  正确响应 %d/4，总耗时 %.2fs" % (ok, elapsed))
    if ok == 4:
        print("  ✅ RPC 往返成功——响应通过伪队列回到【发起连接】")

    # ---------- 约束 2：另一个连接访问伪队列 ----------
    print("\n【约束 2】在【另一个连接】上访问伪队列 %s" % REPLY_Q)
    try:
        c2 = conn()
        ch2 = c2.channel()
        m = ch2.basic_get(REPLY_Q, auto_ack=True)
        print("  结果：返回 %s" % ("(None, None, None)" if m[0] is None else "有数据"))
        c2.close()
    except Exception as e:
        print("  结果：❌ %s" % str(e).split('\n')[0][:90])
        print("  → 伪队列【绑死连接】，别的连接看不见它")

    c.close()

    print("\n" + "=" * 70)
    print("Direct Reply-To 要点")
    print("=" * 70)
    print("1. 伪队列无需声明、不占 broker 资源——比『每请求建临时队列』省得多")
    print("2. 但绑死连接：响应只会回到【发起请求的那条连接】")
    print("3. 因此客户端必须自己保证连接不中断；断了要重发请求")
    print("4. 不适合跨进程/跨服务中转——那是普通回调队列的活")
    return 0


if __name__ == '__main__':
    sys.exit(main())
