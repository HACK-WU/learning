#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 12 实验：RPC 两种回调方案对照
====================================
知识点 1「RPC 与 Direct Reply-To」。

方案对照（这正是本实验的价值）：
  方案 A：Direct Reply-To（reply_to = 'amq.rabbitmq.reply-to'）
          伪队列，免声明、省资源——但【绑死连接】
  方案 B：普通回调队列（exclusive 临时队列）
          要声明一个队列，多一次网络往返——但【不绑连接】

实测结论（本环境）：
  - 方案 A 的两条硬约束已实测确认：
      ① 无响应消费者时发布 → 406 fast reply consumer does not exist
      ② 另一连接访问伪队列 → 404 no queue 'amq.rabbitmq.reply-to'
  - 方案 A 的完整往返在本环境（WSL/Windows + pika 生成器惰性注册）
    未跑通，如实记录
  - 方案 B 完整往返实测成功

⚠️ 只操作集群内资源，不触碰 rabbitmq-learn
"""
import subprocess
import sys
import threading
import time
import uuid

import pika

PORT = 5681
CRED = pika.PlainCredentials('learn', 'learn123')
REPLY_Q_PSEUDO = 'amq.rabbitmq.reply-to'
RPC_Q = 'l12.rpc.cmp'


def conn():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost', port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=60, socket_timeout=60))


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


def fib(n):
    return n if n < 2 else fib(n - 1) + fib(n - 2)


def start_server(c):
    """在同进程内启动服务端（生成器式 consume，独立连接）"""
    srv_conn = conn()
    srv_ch = srv_conn.channel()
    srv_ch.basic_qos(prefetch_count=1)
    gen = srv_ch.consume(RPC_Q, inactivity_timeout=40, auto_ack=False)
    stop = threading.Event()

    def run():
        try:
            for m in gen:
                if stop.is_set() or m[0] is None:
                    break
                method, props, body = m[0], m[1], m[2]
                n = int(body)
                srv_ch.basic_publish(exchange='', routing_key=props.reply_to,
                                     body=str(fib(n)).encode(),
                                     properties=pika.BasicProperties(
                                         correlation_id=props.correlation_id))
                srv_ch.basic_ack(method.delivery_tag)
        except Exception as e:
            print("      [服务端] %s" % str(e)[:70])

    t = threading.Thread(target=run)
    t.start()
    time.sleep(3)
    return stop, t, srv_conn


def cleanup_queues(ch, *qs):
    for q in qs:
        try:
            ch.queue_delete(queue=q)
        except Exception:
            pass


def main():
    print("=" * 72)
    print("课 12 实验：RPC 两种回调方案对照")
    print("=" * 72)

    c = conn()
    ch = c.channel()
    cleanup_queues(ch, RPC_Q)
    time.sleep(1)
    ch.queue_declare(queue=RPC_Q, durable=True,
                     arguments={'x-queue-type': 'quorum'})
    time.sleep(2)

    stop, st, srv_conn = start_server(c)
    d, cc = depth(RPC_Q)
    print("\n  队列 %s：messages=%s consumers=%s（服务端已就绪）" % (RPC_Q, d, cc))

    # ---------------- 方案 B：普通回调队列 ----------------
    print("\n" + "=" * 72)
    print("【方案 B】普通回调队列（exclusive 临时队列）")
    print("=" * 72)
    print("  做法：客户端声明一个 exclusive 队列，把名字放进 reply_to")

    # exclusive 队列由客户端声明
    cb_ch = c.channel()
    qd = cb_ch.queue_declare(queue='', exclusive=True)
    callback_queue = qd.method.queue
    print("  已声明回调队列：%s（exclusive，连接断开即自动删除）" % callback_queue)

    responses_b = {}
    corr_b = {}
    gen_b = cb_ch.consume(callback_queue, inactivity_timeout=25, auto_ack=True)

    # 先预热消费者，再发请求
    pre = threading.Event()
    collected = {}

    def collect_b():
        try:
            for m in gen_b:
                if m[0] is None:
                    break
                collected[m[1].correlation_id] = m[2].decode()
                if len(collected) >= 4:
                    break
        except Exception as e:
            print("      [收响应] %s" % str(e)[:70])

    tb = threading.Thread(target=collect_b)
    tb.start()
    time.sleep(2)

    for n in (5, 10, 15, 20):
        cid = str(uuid.uuid4())
        corr_b[cid] = n
        ch.basic_publish(exchange='', routing_key=RPC_Q,
                         body=str(n).encode(),
                         properties=pika.BasicProperties(
                             reply_to=callback_queue, correlation_id=cid,
                             delivery_mode=2))
    print("  已发送 4 个请求：fib(5) fib(10) fib(15) fib(20)")

    t0 = time.time()
    tb.join(timeout=30)
    elapsed_b = time.time() - t0

    expected = {5: 5, 10: 55, 15: 610, 20: 6765}
    ok_b = 0
    print("")
    print("  | 请求 | 期望 | 实际 |")
    print("  |------|------|------|")
    for cid, n in corr_b.items():
        got = collected.get(cid, '（未收到）')
        good = str(got) == str(expected[n])
        if good:
            ok_b += 1
        print("  | fib(%d) | %d | %s %s |" % (
            n, expected[n], got, "✅" if good else "❌"))
    print("")
    print("  正确 %d/4，耗时 %.2fs" % (ok_b, elapsed_b))
    if ok_b == 4:
        print("  ✅ 方案 B 完整往返成功")

    # ---------------- 方案 A 的约束实测 ----------------
    print("\n" + "=" * 72)
    print("【方案 A】Direct Reply-To 的两条硬约束")
    print("=" * 72)

    print("\n  约束 ①：在【另一个连接】上访问伪队列")
    try:
        c2 = conn()
        ch2 = c2.channel()
        m = ch2.basic_get(REPLY_Q_PSEUDO, auto_ack=True)
        print("    结果：%s" % ("返回空" if m[0] is None else "有数据"))
        c2.close()
    except Exception as e:
        print("    结果：❌ %s" % str(e).split('\n')[0][:80])
        print("    → 伪队列【绑死连接】，其他连接看不见它")

    print("\n  约束 ②：无响应消费者时发布带 reply_to 的消息")
    ach = c.channel()
    try:
        ach.basic_publish(exchange='', routing_key=RPC_Q, body=b'1',
                          properties=pika.BasicProperties(
                              reply_to=REPLY_Q_PSEUDO))
        c.process_data_events(time_limit=1.0)
        time.sleep(1)
        print("    结果：未当场报错")
    except Exception as e:
        print("    结果：❌ %s" % str(e).split('\n')[0][:80])
        print("    → 证实：没有响应消费者，带 reply_to 的发布会被拒绝")

    # ---------------- 结论 ----------------
    print("\n" + "=" * 72)
    print("两种方案怎么选")
    print("=" * 72)
    print("")
    print("| 维度 | Direct Reply-To | 普通回调队列 |")
    print("|------|-----------------|--------------|")
    print("| 是否要声明队列 | 否（伪队列） | 是（exclusive） |")
    print("| broker 资源占用 | 极低 | 每客户端一个临时队列 |")
    print("| 是否绑死连接 | ✅ 绑死 | ❌ 不绑 |")
    print("| 连接断开影响 | 在途响应丢失 | 队列随之删除，需重建 |")
    print("| 跨进程/跨服务中转 | ❌ 不行 | ✅ 可以 |")
    print("| 本环境完整往返 | ⚠️ 未跑通 | ✅ 成功 |")
    print("")
    print("结论：")
    print("  - 短连接、同进程、追求极致轻量 → Direct Reply-To")
    print("  - 需要跨服务中转、长任务、连接可能重连 → 普通回调队列更稳")

    stop.set()
    st.join(timeout=5)
    for x in (srv_conn, c):
        try:
            x.close()
        except Exception:
            pass
    try:
        c3 = conn()
        cleanup_queues(c3.channel(), RPC_Q)
        c3.close()
    except Exception:
        pass
    return 0


if __name__ == '__main__':
    sys.exit(main())
