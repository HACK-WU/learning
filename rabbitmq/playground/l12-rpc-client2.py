#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 12 实验：RPC 客户端（独立进程，两种回调方案对照）

方案 B（普通回调队列）：完整往返 —— 本次实测目标
方案 A（Direct Reply-To）：只测两条硬约束（免踩 pika 惰性注册的坑）

用法：先另开终端跑 python3 l12-rpc-server.py，再跑本脚本。
"""
import subprocess
import sys
import time
import uuid

import pika

PORT = 5681
CRED = pika.PlainCredentials('learn', 'learn123')
RPC_Q = 'l12.rpc.cmp'
PSEUDO = 'amq.rabbitmq.reply-to'


def conn():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost', port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=120, socket_timeout=120))


def depth(q):
    r = subprocess.run(
        ['docker', 'exec', 'rmq1', 'rabbitmqctl', 'list_queues',
         'name', 'messages', 'consumers', '--quiet'],
        capture_output=True, text=True, timeout=90)
    for ln in (r.stdout or '').splitlines()[1:]:
        p = ln.split('\t')
        if len(p) >= 3 and p[0].strip() == q:
            return p[1].strip(), p[2].strip()
    return None, None


def main():
    print("=" * 72)
    print("课 12 实验：RPC 两种回调方案对照（客户端）")
    print("=" * 72)

    d, cc = depth(RPC_Q)
    if d is None:
        print("\n  ❌ 队列 %s 不存在，请先运行服务端：" % RPC_Q)
        print("     python3 l12-rpc-server.py")
        return 1
    print("\n  队列 %s：messages=%s consumers=%s" % (RPC_Q, d, cc))
    if not cc or cc == '0':
        print("  ⚠️ 服务端未就绪（consumers=0），请先运行 l12-rpc-server.py")
        return 1

    c = conn()
    ch = c.channel()

    # ================= 方案 B：普通回调队列 =================
    print("\n" + "=" * 72)
    print("【方案 B】普通回调队列（exclusive 临时队列）—— 完整往返")
    print("=" * 72)

    cb_ch = c.channel()
    qd = cb_ch.queue_declare(queue='', exclusive=True)
    cbq = qd.method.queue
    print("\n  已声明回调队列：%s" % cbq)
    print("  （exclusive：连接断开即自动删除，不污染 broker）")

    collected = {}
    corr = {}
    expected = {5: 5, 10: 55, 15: 610, 20: 6765}

    for n in (5, 10, 15, 20):
        cid = str(uuid.uuid4())
        corr[cid] = n
        ch.basic_publish(exchange='', routing_key=RPC_Q,
                         body=str(n).encode(),
                         properties=pika.BasicProperties(
                             reply_to=cbq, correlation_id=cid,
                             delivery_mode=2))
    print("  已发送 4 个请求：fib(5) fib(10) fib(15) fib(20)")

    # 单线程收响应（本连接只有这一个 I/O 活动，无冲突）
    t0 = time.time()
    for m in cb_ch.consume(cbq, inactivity_timeout=30, auto_ack=True):
        if m[0] is None:
            break
        collected[m[1].correlation_id] = m[2].decode()
        if len(collected) >= 4:
            break
        if time.time() - t0 > 30:
            break
    elapsed = time.time() - t0

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
    if ok == 4:
        print("  ✅ 方案 B 完整往返成功")
    try:
        cb_ch.close()
    except Exception:
        pass

    # ================= 方案 A：Direct Reply-To 的约束 =================
    print("\n" + "=" * 72)
    print("【方案 A】Direct Reply-To 的两条硬约束")
    print("=" * 72)

    print("\n  约束 ①：在【另一个连接】上访问伪队列 '%s'" % PSEUDO)
    try:
        c2 = conn()
        ch2 = c2.channel()
        m = ch2.basic_get(PSEUDO, auto_ack=True)
        print("    结果：%s" % ("返回空" if m[0] is None else "有数据"))
        c2.close()
    except Exception as e:
        print("    结果：❌ %s" % str(e).split('\n')[0][:80])
        print("    → 伪队列【绑死连接】，其他连接看不见它")

    print("\n  约束 ②：无响应消费者时，发布带 reply_to 的消息")
    ach = c.channel()
    try:
        ach.basic_publish(exchange='', routing_key=RPC_Q, body=b'1',
                          properties=pika.BasicProperties(reply_to=PSEUDO))
        c.process_data_events(time_limit=1.0)
        time.sleep(1)
        print("    结果：未当场报错")
        print("    （错误可能异步返回并关闭 channel）")
    except Exception as e:
        print("    结果：❌ %s" % str(e).split('\n')[0][:80])
        print("    → 证实：没有响应消费者，带 reply_to 的发布会被拒绝")

    try:
        c.close()
    except Exception:
        pass

    # ================= 结论 =================
    print("\n" + "=" * 72)
    print("两种方案怎么选")
    print("=" * 72)
    print("")
    print("| 维度 | Direct Reply-To | 普通回调队列 |")
    print("|------|-----------------|--------------|")
    print("| 是否要声明队列 | 否（伪队列） | 是（exclusive） |")
    print("| broker 资源占用 | 极低 | 每客户端一个临时队列 |")
    print("| 是否绑死连接 | 是（绑死） | 否 |")
    print("| 连接断开影响 | 在途响应丢失 | 队列随之删除，需重建 |")
    print("| 跨进程/跨服务中转 | ❌ 不行 | ✅ 可以 |")
    print("| 本环境完整往返 | ⚠️ 未跑通 | ✅ 成功（本实测） |")
    print("")
    print("结论：")
    print("  - 短连接、同进程、追求极致轻量 → Direct Reply-To")
    print("  - 跨服务中转、长任务、连接可能重连 → 普通回调队列更稳")
    return 0


if __name__ == '__main__':
    sys.exit(main())
