#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 12 实验：跨信道的 Direct Reply-To 到底有没有收到响应？

上一版（l12-drt-crosschannel.py）只检查了「有没有报错」，
对照组 1（跨信道）显示"无错误"——但这【不等于响应到达了】。

  消息被服务端消费 → 服务端发布响应 → 若没有消费者，响应被静默丢弃
  服务端不会报错，客户端也不会报错，只是永远等不到。

所以本脚本改用真正的判据：【响应到底收没收到】。

方法：三个对照组都发布请求，然后各自等 6 秒看有没有响应回来。
  A. 跨信道（消费 A / 发布 B）
  B. 同信道但顺序颠倒（先发后注册）—— 已知会 406
  C. 同信道 + 先注册后发布（正例）
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


def wait_reply(ch, cid, timeout=6.0):
    """在给定信道上等响应，返回 (是否收到, 错误字符串)。"""
    try:
        for m in ch.consume(PSEUDO, inactivity_timeout=timeout,
                            auto_ack=True):
            if m[0] is None:
                return False, None
            props, body = m[1], m[2]
            if props.correlation_id == cid:
                return True, body.decode()
    except Exception as e:
        return False, "%s: %s" % (type(e).__name__,
                                  str(e).split('\n')[0][:90])
    return False, None


def newconn():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost', port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=120, socket_timeout=120))


def main():
    print("=" * 72)
    print("课 12 实验：跨信道到底收没收到响应？（以响应到达为判据）")
    print("=" * 72)

    cc = server_ready()
    if not cc or cc == '0':
        print("\n  ❌ 服务端未就绪，请先运行：python3 l12-drt-server.py &")
        return 1
    print("\n  服务端已就绪：%s consumers=%s" % (RPC_Q, cc))

    # ================= A. 跨信道 =================
    print("\n" + "-" * 72)
    print("A. 跨信道：消费者注册在信道 A，请求从信道 B 发出")
    print("-" * 72)
    conn = newconn()
    chA = conn.channel()
    chB = conn.channel()
    try:
        next(chA.consume(PSEUDO, auto_ack=True, inactivity_timeout=0.1))
    except StopIteration:
        pass
    print("  信道 A 已注册伪队列消费者")
    cid = str(uuid.uuid4())
    try:
        chB.basic_publish(exchange='', routing_key=RPC_Q, body=b'5',
                          properties=pika.BasicProperties(
                              reply_to=PSEUDO, correlation_id=cid))
        print("  信道 B 已发布请求（fib(5)）")
    except Exception as e:
        print("  发布即报错：%s" % str(e).split('\n')[0][:90])
    print("  → 在信道 A 上等 6 秒看响应是否到达…")
    got, val = wait_reply(chA, cid, timeout=6.0)
    if got:
        print("  结果：✅ 响应到达（=%s）" % val)
        resA = "✅ 收到响应 %s" % val
    else:
        print("  结果：❌ 6 秒内未收到响应（%s）" % (val or "超时"))
        resA = "❌ 未收到响应（无报错，静默丢失）"
    try:
        conn.close()
    except Exception:
        pass

    # ================= B. 顺序颠倒 =================
    print("\n" + "-" * 72)
    print("B. 同信道，但先 publish 再注册消费者")
    print("-" * 72)
    conn = newconn()
    ch = conn.channel()
    cid = str(uuid.uuid4())
    err = None
    try:
        ch.basic_publish(exchange='', routing_key=RPC_Q, body=b'5',
                         properties=pika.BasicProperties(
                             reply_to=PSEUDO, correlation_id=cid))
        print("  已发布请求（fib(5)），publish 当场未报错")
    except Exception as e:
        err = "%s: %s" % (type(e).__name__, str(e).split('\n')[0][:90])
    if err is None:
        try:
            got, val = wait_reply(ch, cid, timeout=6.0)
            if got:
                print("  结果：✅ 响应到达（=%s）" % val)
                resB = "✅ 收到响应 %s" % val
            else:
                print("  结果：❌ 未收到响应（%s）" % (val or "超时"))
                resB = "❌ 未收到响应"
        except Exception as e:
            print("  等待时报错：❌ %s" % str(e).split('\n')[0][:90])
            resB = "❌ %s" % str(e).split('\n')[0][:50]
    else:
        print("  结果：❌ %s" % err)
        resB = "❌ 406"
    try:
        conn.close()
    except Exception:
        pass

    # ================= C. 正例 =================
    print("\n" + "-" * 72)
    print("C. 正例：同信道 + 先注册后发布")
    print("-" * 72)
    conn = newconn()
    ch = conn.channel()
    try:
        next(ch.consume(PSEUDO, auto_ack=True, inactivity_timeout=0.1))
    except StopIteration:
        pass
    cid = str(uuid.uuid4())
    ch.basic_publish(exchange='', routing_key=RPC_Q, body=b'5',
                     properties=pika.BasicProperties(
                         reply_to=PSEUDO, correlation_id=cid))
    got, val = wait_reply(ch, cid, timeout=6.0)
    if got:
        print("  结果：✅ 响应到达（=%s）" % val)
        resC = "✅ 收到响应 %s" % val
    else:
        print("  结果：❌ 未收到响应（%s）" % (val or "超时"))
        resC = "❌ 未收到响应"
    try:
        conn.close()
    except Exception:
        pass

    print("\n" + "=" * 72)
    print("结论（判据 = 响应是否真的到达）")
    print("=" * 72)
    print("")
    print("| 用法 | 结果 |")
    print("|------|------|")
    print("| A 跨信道（消费 A / 发布 B） | %s |" % resA)
    print("| B 同信道但先发后注册 | %s |" % resB)
    print("| C 同信道 + 先注册后发布 | %s |" % resC)
    print("")
    return 0


if __name__ == '__main__':
    sys.exit(main())
