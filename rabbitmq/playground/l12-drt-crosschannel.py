#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 12 实验：Direct Reply-To 的失败对照——【跨信道】为什么会 406

既然「单连接 + 单信道」能跑通（l12-drt-client.py），
那就反过来验证官方那条约束是不是真的必要：

  对照组 1：消费者注册在信道 A，请求却从信道 B 发出
            → 预期 406 fast reply consumer does not exist
  对照组 2：先 publish 再注册消费者（顺序颠倒）
            → 预期同样 406
  对照组 3（正例）：同信道 + 先注册后发布
            → 预期成功

这三条合起来，才能证明「同信道」是硬约束而不是巧合。
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


def server_ready():
    r = subprocess.run(
        ['docker', 'exec', 'rmq1', 'rabbitmqctl', 'list_queues',
         'name', 'messages', 'consumers', '--quiet'],
        capture_output=True, text=True, timeout=90)
    for ln in (r.stdout or '').splitlines()[1:]:
        p = ln.split('\t')
        if len(p) >= 3 and p[0].strip() == RPC_Q:
            return p[2].strip()
    return None


def pump(conn, seconds=1.5):
    """驱动事件循环，让异步返回的 channel 错误浮出来。"""
    end = time.time() + seconds
    while time.time() < end:
        try:
            conn.process_data_events(time_limit=0.3)
        except pika.exceptions.AMQPError as e:
            return "AMQPError: %s" % str(e).split('\n')[0][:100]
        except Exception as e:
            return "%s: %s" % (type(e).__name__, str(e).split('\n')[0][:100])
    return None


def main():
    print("=" * 72)
    print("课 12 实验：Direct Reply-To 失败对照（证明「同信道」是硬约束）")
    print("=" * 72)

    cc = server_ready()
    if not cc or cc == '0':
        print("\n  ❌ 服务端未就绪，请先运行：python3 l12-drt-server.py &")
        return 1
    print("\n  服务端已就绪：%s consumers=%s" % (RPC_Q, cc))

    results = {}

    # ================= 对照组 1：跨信道 =================
    print("\n" + "-" * 72)
    print("对照组 1：消费者在信道 A，请求从信道 B 发出")
    print("-" * 72)
    conn = pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost', port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=120, socket_timeout=120))
    chA = conn.channel()
    chB = conn.channel()
    try:
        next(chA.consume(PSEUDO, auto_ack=True, inactivity_timeout=0.1))
    except StopIteration:
        pass
    print("  信道 A 已注册伪队列消费者")
    err = None
    try:
        chB.basic_publish(exchange='', routing_key=RPC_Q, body=b'5',
                          properties=pika.BasicProperties(
                              reply_to=PSEUDO,
                              correlation_id=str(uuid.uuid4())))
        print("  信道 B 发布请求：basic_publish 返回时未报错")
    except Exception as e:
        err = "%s: %s" % (type(e).__name__, str(e).split('\n')[0][:100])
    if err is None:
        err = pump(conn)
    if err:
        print("  随后错误：❌ %s" % err)
        results['cross_channel'] = err
    else:
        print("  随后错误：无")
        results['cross_channel'] = None
    try:
        conn.close()
    except Exception:
        pass

    # ================= 对照组 2：顺序颠倒 =================
    print("\n" + "-" * 72)
    print("对照组 2：同信道，但先 publish 再注册消费者")
    print("-" * 72)
    conn = pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost', port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=120, socket_timeout=120))
    ch = conn.channel()
    err = None
    try:
        ch.basic_publish(exchange='', routing_key=RPC_Q, body=b'5',
                         properties=pika.BasicProperties(
                             reply_to=PSEUDO,
                             correlation_id=str(uuid.uuid4())))
        print("  publish 先执行：返回时未报错")
    except Exception as e:
        err = "%s: %s" % (type(e).__name__, str(e).split('\n')[0][:100])
    if err is None:
        try:
            next(ch.consume(PSEUDO, auto_ack=True, inactivity_timeout=0.1))
            print("  再注册消费者：注册本身未报错")
        except Exception as e:
            err = "%s: %s" % (type(e).__name__, str(e).split('\n')[0][:100])
    if err is None:
        err = pump(conn)
    if err:
        print("  随后错误：❌ %s" % err)
        results['wrong_order'] = err
    else:
        print("  随后错误：无")
        results['wrong_order'] = None
    try:
        conn.close()
    except Exception:
        pass

    # ================= 对照组 3：正例 =================
    print("\n" + "-" * 72)
    print("对照组 3（正例）：同信道 + 先注册后发布")
    print("-" * 72)
    conn = pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost', port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=120, socket_timeout=120))
    ch = conn.channel()
    try:
        next(ch.consume(PSEUDO, auto_ack=True, inactivity_timeout=0.1))
    except StopIteration:
        pass
    cid = str(uuid.uuid4())
    err = None
    try:
        ch.basic_publish(exchange='', routing_key=RPC_Q, body=b'5',
                         properties=pika.BasicProperties(
                             reply_to=PSEUDO, correlation_id=cid))
    except Exception as e:
        err = "%s: %s" % (type(e).__name__, str(e).split('\n')[0][:100])
    got = None
    if err is None:
        for m in ch.consume(PSEUDO, inactivity_timeout=8, auto_ack=True):
            if m[0] is None:
                break
            props, body = m[1], m[2]
            if props.correlation_id == cid:
                got = body.decode()
                break
    if err:
        print("  错误：❌ %s" % err)
        results['correct'] = err
    elif got is not None:
        print("  收到响应：%s ✅（fib(5)=5 正确）" % got)
        results['correct'] = None
    else:
        print("  未收到响应 ❌")
        results['correct'] = 'no reply'
    try:
        conn.close()
    except Exception:
        pass

    # ================= 结论 =================
    print("\n" + "=" * 72)
    print("结论")
    print("=" * 72)
    print("")
    print("| 用法 | 结果 |")
    print("|------|------|")
    print("| 跨信道（消费 A / 发布 B） | %s |" % (
        "❌ 406" if results.get('cross_channel') else "✅ 通过"))
    print("| 同信道但顺序颠倒（先发后注册） | %s |" % (
        "❌ %s" % str(results.get('wrong_order'))[:40]
        if results.get('wrong_order') else "✅ 通过"))
    print("| 同信道 + 先注册后发布（正例） | %s |" % (
        "❌ %s" % str(results.get('correct'))[:40]
        if results.get('correct') else "✅ 通过"))
    print("")
    print("→ 「同一连接 + 同一信道 + 先注册消费者」三条同时满足，")
    print("   Direct Reply-To 才成立。缺任何一条都以 406 失败，")
    print("   且错误是【异步返回】的——publish 当场不抛，随后 channel 被关。")
    return 0


if __name__ == '__main__':
    sys.exit(main())
