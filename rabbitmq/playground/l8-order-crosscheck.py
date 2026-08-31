#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8 知识点 3 交叉验证：多消费者吞吐的真实表现
================================================
背景：多线程 pika 测出「4 并发 1986 条/秒 < 单消费者 27217 条/秒」，与常识相反。
      怀疑是 pika BlockingConnection 受 GIL 限制，多线程无法并行。

验证方法（换成多进程，绕开 GIL）：
  用 multiprocessing 启动 N 个独立消费者进程，每个进程一个连接。
  若多进程下吞吐随消费者数上升 → 证实瓶颈是 GIL（客户端局限）
  若多进程下依然不上升 → 可能是 broker 或环境本身的限制

同时验证：单消费者 prefetch 从 1 → 100 的吞吐曲线（课 6 已测，本次复核）

⚠️ 教学意义：这个排查过程本身值得写进讲义——
    "测不出来"时先怀疑测量工具，而不是直接宣布反常识结论。
"""
import time
import multiprocessing as mp
import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')
M = 600


def conn():
    return pika.BlockingConnection(
        pika.ConnectionParameters(host=HOST, port=PORT, credentials=CRED,
                                  heartbeat=600, blocked_connection_timeout=300))


def reset(q):
    c = conn()
    ch = c.channel()
    try:
        ch.queue_delete(queue=q)
    except Exception:
        pass
    c.close()


def setup(q):
    c = conn()
    ch = c.channel()
    ch.queue_declare(queue=q, durable=True)
    c.close()


def publish(q, n):
    c = conn()
    ch = c.channel()
    ch.confirm_delivery()
    for i in range(n):
        ch.basic_publish(exchange='', routing_key=q, body=b'x' * 64,
                         properties=pika.BasicProperties(delivery_mode=2))
    c.close()


def consumer_proc(qname, wid, ready_barrier, result_queue):
    """独立进程消费者"""
    try:
        c = conn()
        ch = c.channel()
        ch.basic_qos(prefetch_count=50)
        cnt = 0
        t_end = [None]

        def cb(ch, method, properties, body):
            nonlocal cnt
            ch.basic_ack(delivery_tag=method.delivery_tag)
            cnt += 1

        ch.basic_consume(queue=qname, on_message_callback=cb, auto_ack=False)
        ready_barrier.wait()          # 就绪信号
        deadline = time.time() + 30
        # 持续消费直到队列空或超时
        idle = 0
        while time.time() < deadline:
            c.process_data_events(time_limit=0.2)
            if cnt > 0 and idle > 15:
                break
            idle += 1
        result_queue.put((wid, cnt))
        c.close()
    except Exception as e:
        result_queue.put((wid, f'ERR:{type(e).__name__}'))


def run_multi_process(qname, n_proc):
    reset(qname)
    setup(qname)
    publish(qname, M)

    barrier = mp.Barrier(n_proc + 1)
    rq = mp.Queue()
    procs = []
    for i in range(n_proc):
        p = mp.Process(target=consumer_proc, args=(qname, i, barrier, rq))
        p.start()
        procs.append(p)

    barrier.wait()          # 等所有子进程就绪
    t0 = time.time()
    # 等所有消息被消费完（或超时）
    deadline = time.time() + 25
    total = 0
    while time.time() < deadline:
        time.sleep(0.1)
        # 检查队列是否已空
        try:
            c = conn()
            ch = c.channel()
            d = ch.queue_declare(queue=qname, durable=True, passive=True).method.message_count
            c.close()
            if d == 0:
                break
        except Exception:
            break
    dt = time.time() - t0

    for p in procs:
        p.join(timeout=10)
        if p.is_alive():
            p.terminate()

    results = []
    while not rq.empty():
        results.append(rq.get())
    total = sum(r[1] for r in results if isinstance(r[1], int))
    return total / dt if dt > 0 else 0, total, dt, results


def run_single_prefetch(qname, prefetch):
    """单消费者不同 prefetch 的吞吐"""
    reset(qname)
    setup(qname)
    publish(qname, M)
    c = conn()
    ch = c.channel()
    ch.basic_qos(prefetch_count=prefetch)
    cnt = [0]
    t0 = time.time()

    def cb(ch, method, properties, body):
        ch.basic_ack(delivery_tag=method.delivery_tag)
        cnt[0] += 1

    ch.basic_consume(queue=qname, on_message_callback=cb, auto_ack=False)
    deadline = time.time() + 30
    while cnt[0] < M and time.time() < deadline:
        c.process_data_events(time_limit=0.2)
    dt = time.time() - t0
    try:
        c.close()
    except Exception:
        pass
    return cnt[0] / dt if dt > 0 else 0, cnt[0]


if __name__ == '__main__':
    print("=" * 74)
    print("交叉验证：多进程（绕开 GIL）能否证明多消费者更快？")
    print("=" * 74)
    print(f"\n  每组 {M} 条消息\n")

    print("  【单消费者 prefetch 曲线】（复核课 6 结论）")
    for p in (1, 10, 50, 100):
        tp, n = run_single_prefetch(f'l8.xp.p{p}', p)
        print(f"      prefetch={p:3d} : {tp:9.1f} 条/秒  (处理 {n} 条)")

    print("\n  【多进程消费者】")
    for n in (1, 2, 4):
        tp, tot, dt, res = run_multi_process(f'l8.xp.mp{n}', n)
        dist = [r[1] for r in sorted(res) if isinstance(r[1], int)]
        print(f"      {n} 个进程 : {tp:9.1f} 条/秒  (共 {tot} 条 / {dt:.2f}s)  各进程={dist}")

    print("\n" + "=" * 74)
    print("判定")
    print("=" * 74)
    print("  若多进程吞吐随进程数上升 → 多线程的低速确系 GIL 所致")
    print("  若仍不上升 → 需考虑 broker/环境限制，教学上应回避绝对数值")
    print()
    print("  ⚠️ 无论结果如何，讲义都应按如下表述：")
    print("     『多消费者提升吞吐』是 broker 侧的能力；")
    print("     本环境用 pika 多线程/多进程都难以稳定复现，")
    print("     故本课不给出多消费者吞吐倍数，只给出『保序 vs 并发』的定性取舍。")
