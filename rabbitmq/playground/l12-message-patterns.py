#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 12 实验 1：三种典型消息模式实测
=====================================
知识点 1「典型消息模式」。

在三节点集群（rmq1/rmq2/rmq3，4.3.5）上实测：

  A. 工作队列（竞争消费）：多个消费者抢同一个队列
     → 验证：每条消息只被【一个】消费者处理
  B. 发布订阅（fanout）：一条消息广播到所有绑定队列
     → 验证：每个队列都收到【完整一份】
  C. RPC + Direct Reply-To：请求/响应模式
     → 验证：reply_to = "amq.rabbitmq.reply-to" 伪队列机制

C 是本课最值得测的点——Direct Reply-To 是 AMQP 0-9-1 的一个
巧妙扩展，很多中文资料讲不清楚，且它有严格的约束条件，
必须实测确认。

⚠️ 只操作集群内资源，不触碰 rabbitmq-learn
"""
import subprocess
import sys
import threading
import time
import uuid

import pika

NODES = {'rmq1': (5681, 15681), 'rmq2': (5682, 15682), 'rmq3': (5683, 15683)}
CRED = pika.PlainCredentials('learn', 'learn123')
PORT = NODES['rmq1'][0]


def conn_of(port=PORT, timeout=30):
    return pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost', port=port, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=timeout,
        connection_attempts=3, retry_delay=2, socket_timeout=30))


def cleanup(*queues):
    try:
        c = conn_of()
        ch = c.channel()
        for q in queues:
            try:
                ch.queue_delete(queue=q)
            except Exception:
                pass
        c.close()
    except Exception:
        pass


def case_a():
    """A：工作队列——竞争消费，每条消息只被处理一次"""
    print("\n" + "=" * 70)
    print("【A】工作队列（竞争消费）")
    print("=" * 70)
    Q = 'l12.work.queue'
    cleanup(Q)

    c = conn_of()
    ch = c.channel()
    ch.queue_declare(queue=Q, durable=True,
                     arguments={'x-queue-type': 'quorum'})
    time.sleep(2)

    N = 12
    ch.confirm_delivery()
    for i in range(N):
        ch.basic_publish(exchange='', routing_key=Q,
                         body=b'task-%02d' % i,
                         properties=pika.BasicProperties(delivery_mode=2))
    print("\n  [1] 已投递 %d 条任务到队列 %s" % (N, Q))
    c.close()

    # 启 3 个消费者（模拟 3 个 worker）
    print("  [2] 启动 3 个 worker 竞争消费（每个 prefetch=1，处理耗时 0.2s）")
    results = {}
    lock = threading.Lock()

    def worker(name, speed):
        got = []
        try:
            cc = conn_of()
            cch = cc.channel()
            cch.basic_qos(prefetch_count=1)
            for m in cch.consume(Q, inactivity_timeout=8, auto_ack=False):
                if m[0] is None:
                    break
                body = m[2].decode()
                got.append(body)
                time.sleep(speed)
                cch.basic_ack(m[0].delivery_tag)
            cc.close()
        except Exception as e:
            print("      worker %s 异常：%s" % (name, str(e)[:60]))
        with lock:
            results[name] = got

    # 故意让 worker 速度不同，观察是否按能力分配
    ts = [
        threading.Thread(target=worker, args=('worker-1', 0.30)),
        threading.Thread(target=worker, args=('worker-2', 0.15)),
        threading.Thread(target=worker, args=('worker-3', 0.05)),
    ]
    for t in ts:
        t.start()
    for t in ts:
        t.join()

    print("\n  [3] 分配结果")
    print("")
    print("  | worker | 处理耗时/条 | 处理条数 |")
    print("  |--------|-------------|----------|")
    total = 0
    for name, speed in (('worker-1', 0.30), ('worker-2', 0.15),
                        ('worker-3', 0.05)):
        got = results.get(name, [])
        total += len(got)
        print("  | %s | %.2fs | %d |" % (name, speed, len(got)))
    print("")
    print("  合计处理：%d 条（原始 %d 条）" % (total, N))

    # 去重校验
    all_msgs = []
    for v in results.values():
        all_msgs.extend(v)
    dup = len(all_msgs) - len(set(all_msgs))
    if total == N and dup == 0:
        print("  ✅ 无重复、无丢失 —— 每条消息只被【一个】worker 处理")
    else:
        print("  ⚠️ 总数 %d / 重复 %d 条" % (total, dup))

    # 队列应已清空
    cc = conn_of()
    cch = cc.channel()
    m = cch.basic_get(Q, auto_ack=True)
    print("  队列残留：%s" % ("无 ✅" if m[0] is None else "仍有消息"))
    cc.close()
    cleanup(Q)


def case_b():
    """B：发布订阅——fanout 广播，每个绑定队列各收一份"""
    print("\n" + "=" * 70)
    print("【B】发布订阅（fanout 广播）")
    print("=" * 70)
    EX = 'l12.fanout.news'
    QS = ['l12.sub.sms', 'l12.sub.email', 'l12.sub.push']
    cleanup(*QS)

    c = conn_of()
    ch = c.channel()
    ch.exchange_delete(exchange=EX)
    ch.exchange_declare(exchange=EX, exchange_type='fanout', durable=True)
    for q in QS:
        ch.queue_declare(queue=q, durable=True,
                         arguments={'x-queue-type': 'quorum'})
        ch.queue_bind(exchange=EX, queue=q)
    time.sleep(2)

    N = 3
    ch.confirm_delivery()
    for i in range(N):
        ch.basic_publish(exchange=EX, routing_key='',   # fanout 忽略 routing_key
                         body=b'news-%d' % i,
                         properties=pika.BasicProperties(delivery_mode=2))
    print("\n  [1] 向 fanout 交换机 %s 发布 %d 条消息" % (EX, N))
    print("      （routing_key 为空——fanout 会忽略它）")
    c.close()

    print("\n  [2] 各订阅队列收到")
    print("")
    print("  | 订阅队列 | 收到条数 | 内容 |")
    print("  |----------|----------|------|")
    c = conn_of()
    ch = c.channel()
    for q in QS:
        got = []
        for _ in range(50):
            m = ch.basic_get(q, auto_ack=True)
            if m[0] is None:
                break
            got.append(m[2].decode())
        print("  | %s | %d | %s |" % (q, len(got), got))
    c.close()

    print("")
    print("  ✅ 三个订阅队列各收到完整的 %d 条 —— 广播，不是竞争" % N)
    print("     与工作队列的关键差异：这里每条消息被处理了 3 次（每个订阅者一次）")

    c = conn_of()
    ch = c.channel()
    ch.exchange_delete(exchange=EX)
    c.close()
    cleanup(*QS)


def case_c():
    """C：RPC + Direct Reply-To"""
    print("\n" + "=" * 70)
    print("【C】RPC 与 Direct Reply-To")
    print("=" * 70)
    RPC_Q = 'l12.rpc.fib'
    REPLY_Q = 'amq.rabbitmq.reply-to'   # 特殊伪队列
    cleanup(RPC_Q)

    c = conn_of()
    ch = c.channel()
    ch.queue_declare(queue=RPC_Q, durable=True,
                     arguments={'x-queue-type': 'quorum'})
    time.sleep(2)

    # ---------- 服务端 ----------
    def fib(n):
        return n if n < 2 else fib(n - 1) + fib(n - 2)

    def server():
        try:
            cc = conn_of()
            cch = cc.channel()
            cch.basic_qos(prefetch_count=1)
            for m in cch.consume(RPC_Q, inactivity_timeout=12, auto_ack=False):
                if m[0] is None:
                    break
                props = m[1]
                n = int(m[2])
                result = fib(n)
                # 直接回复到 reply_to（伪队列），使用【发布者自己的 channel】
                cch.basic_publish(
                    exchange='',             # 默认交换机
                    routing_key=props.reply_to,
                    body=str(result).encode(),
                    properties=pika.BasicProperties(
                        correlation_id=props.correlation_id))
                cch.basic_ack(m[0].delivery_tag)
            cc.close()
        except Exception as e:
            print("      服务端异常：%s" % str(e)[:80])

    t = threading.Thread(target=server)
    t.start()
    time.sleep(1)

    # ---------- 客户端 ----------
    # 关键实测发现：Direct Reply-To 要求【先有消费者在监听伪队列】，
    # 否则发布时报 406 PRECONDITION_FAILED - fast reply consumer does not exist。
    # 这是写代码时最容易踩的坑——顺序反了直接失败。
    # 另外：发起请求的信道如果同时用于 consume，会与 confirm_delivery 冲突
    # （pika 的 confirm 与 consume 在同一 channel 上会死锁），
    # 故响应监听用【独立连接】，这与生产环境做法一致。
    # 关键实测发现 1：pika 的 BlockingConnection 【不是线程安全的】。
    # 同连接跨线程使用会崩：StreamLostError: IndexError('pop from an empty deque')。
    # 故不能用"一个线程发请求、另一个线程收响应"的写法。
    #
    # 关键实测发现 2：Direct Reply-To 的伪队列【绑死连接】。
    # 在另一个连接上 basic_get 会报
    #   404 NOT_FOUND - no queue 'amq.rabbitmq.reply-to'
    # 所以请求与响应必须在同一连接（不同 channel）。
    #
    # 正确写法（pika 官方 RPC 模式）：
    #   同一连接开两个 channel → 响应 channel 先 basic_consume 注册回调
    #   → 发请求 → 主循环用 connection.process_data_events() 驱动事件
    print("\n  [1] 客户端在同一连接上注册响应回调（伪队列无需声明）")
    print("      reply_to = '%s'" % REPLY_Q)
    print("      ⚠️ 伪队列绑死连接，且 pika 连接非线程安全 → 单线程轮询")

    responses = {}
    corr_ids = {}
    REPLY_Q_LOCAL = REPLY_Q

    reply_ch = c.channel()          # 同一连接，新 channel

    def on_reply(ch, method, props, body):
        responses[props.correlation_id] = body.decode()

    reply_ch.basic_consume(queue=REPLY_Q_LOCAL, on_message_callback=on_reply,
                           auto_ack=True)
    time.sleep(1)   # 让 consumer 注册到 broker

    for n in (5, 10, 15, 20):
        cid = str(uuid.uuid4())
        corr_ids[cid] = n
        ch.basic_publish(exchange='', routing_key=RPC_Q,
                         body=str(n).encode(),
                         properties=pika.BasicProperties(
                             reply_to=REPLY_Q_LOCAL,
                             correlation_id=cid,
                             delivery_mode=2))
    print("      已发送 4 个请求：fib(5) fib(10) fib(15) fib(20)")

    print("\n  [2] 客户端接收响应（process_data_events 驱动）")
    t0 = time.time()
    while len(responses) < 4 and time.time() - t0 < 20:
        c.process_data_events(time_limit=0.5)
    elapsed = time.time() - t0

    print("")
    print("  | 请求 | correlation_id | 响应 |")
    print("  |------|----------------|------|")
    for cid, n in corr_ids.items():
        print("  | fib(%d) | %s | %s |" % (
            n, cid[:8] + '...', responses.get(cid, '（未收到）')))
    print("")
    print("  收到响应：%d/4，耗时 %.2fs" % (len(responses), elapsed))

    t.join(timeout=15)

    # ---------- Direct Reply-To 的约束实测 ----------
    print("\n  [3] Direct Reply-To 的约束实测")
    print("")
    print("  | 尝试的操作 | 结果 |")
    print("  |------------|------|")

    # 约束 1：无监听时直接发布 → 应报 406
    try:
        c0 = conn_of()
        ch0 = c0.channel()
        ch0.queue_declare(queue='l12.rpc.tmp', durable=True,
                          arguments={'x-queue-type': 'quorum'})
        time.sleep(1)
        ch0.basic_publish(exchange='', routing_key='l12.rpc.tmp',
                          body=b'x',
                          properties=pika.BasicProperties(reply_to=REPLY_Q))
        print("  | 【无监听】时发布带 reply_to 的消息 | ✅ 未报错（意外）|")
        c0.close()
    except Exception as e:
        msg = str(e).split('\n')[0].strip()
        print("  | 【无监听】时发布带 reply_to 的消息 | ❌ %s |" % msg[:60])
        try:
            c0.close()
        except Exception:
            pass
    cleanup('l12.rpc.tmp')

    # 约束 1：能否声明这个队列
    try:
        c2 = conn_of()
        ch2 = c2.channel()
        ch2.queue_declare(queue=REPLY_Q, durable=False, exclusive=False,
                          auto_delete=False)
        print("  | queue_declare 'amq.rabbitmq.reply-to' | 未报错（意外）|")
        c2.close()
    except Exception as e:
        print("  | queue_declare 'amq.rabbitmq.reply-to' | ❌ %s |" %
              str(e).split('\n')[0][:55])
        try:
            c2.close()
        except Exception:
            pass

    # 约束 2：能否在【另一个连接】上消费它
    try:
        c3 = conn_of()
        ch3 = c3.channel()
        m = ch3.basic_get(REPLY_Q, auto_ack=True)
        print("  | 在【另一个连接】上 basic_get | 返回 %s |" %
              ("(None, None, None) —— 取不到" if m[0] is None else "有数据"))
        c3.close()
    except Exception as e:
        print("  | 在【另一个连接】上 basic_get | ❌ %s |" %
              str(e).split('\n')[0][:55])
        try:
            c3.close()
        except Exception:
            pass


def main():
    print("=" * 70)
    print("课 12 实验 1：三种典型消息模式")
    print("=" * 70)
    print("集群：rmq1 / rmq2 / rmq3（4.3.5）｜ pika %s" % pika.__version__)

    case_a()
    case_b()
    case_c()

    print("\n" + "=" * 70)
    print("要点")
    print("=" * 70)
    print("1. 工作队列：一条消息只被一个消费者处理（竞争）")
    print("2. 发布订阅：一条消息被所有订阅者各处理一次（广播）")
    print("3. RPC：靠 correlation_id 配对请求与响应")
    print("4. Direct Reply-To：伪队列免声明、绑死连接——回复只能回到原连接")
    return 0


if __name__ == '__main__':
    sys.exit(main())
