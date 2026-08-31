#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 6 实测 10：预取与公平分发

要验证的三件事：
1. prefetch 无上限（默认）时，先启动的消费者会抢空队列 → 分发不公平
2. prefetch_count=N 时，每个消费者手上的未确认消息不超过 N → 快者多劳
3. prefetch 取值与吞吐/内存的权衡：太小则 RTT 占比高、吞吐低

关键测量：让两个消费者**处理速度不同**（一个 sleep 0.01s，一个 sleep 0.2s），
看最终各自处理了多少条。
"""
import subprocess
import threading
import time
import pika

CRED = pika.PlainCredentials('learn', 'learn123')
PARAMS = pika.ConnectionParameters(host='localhost', port=5672, credentials=CRED)
Q = 'l6_fair'


def reset():
    c = pika.BlockingConnection(PARAMS); ch = c.channel()
    ch.queue_declare(queue=Q, durable=True); ch.queue_purge(Q); c.close()


def publish(n):
    c = pika.BlockingConnection(PARAMS); ch = c.channel()
    ch.queue_declare(queue=Q, durable=True)
    for i in range(n):
        ch.basic_publish(exchange='', routing_key=Q, body=f'task-{i}'.encode(),
                         properties=pika.BasicProperties(delivery_mode=2))
    c.close()


def stats():
    out = subprocess.run(
        ['docker', 'exec', 'rabbitmq-learn', 'rabbitmqctl', 'list_queues',
         'name', 'messages_ready', 'messages_unacknowledged', '-q'],
        capture_output=True, text=True).stdout
    for line in out.strip().splitlines():
        p = line.split('\t')
        if len(p) == 3 and p[0] == Q:
            return int(p[1]), int(p[2])
    return 0, 0


class Worker(threading.Thread):
    """消费者：处理速度由 sleep 模拟"""

    def __init__(self, name, work_time, prefetch, budget_sec=6.0):
        super().__init__(daemon=True)
        self.name_ = name
        self.work_time = work_time
        self.prefetch = prefetch
        self.budget = budget_sec
        self.count = 0
        self.stopped = False

    def run(self):
        c = pika.BlockingConnection(PARAMS)
        ch = c.channel()
        ch.queue_declare(queue=Q, durable=True)
        if self.prefetch:
            ch.basic_qos(prefetch_count=self.prefetch)
        deadline = time.time() + self.budget
        for m, props, body in ch.consume(queue=Q, auto_ack=False,
                                         inactivity_timeout=1.0):
            if self.stopped or time.time() > deadline:
                break
            if m is None:
                continue
            time.sleep(self.work_time)      # 模拟处理耗时
            ch.basic_ack(delivery_tag=m.delivery_tag)
            self.count += 1
        try:
            ch.cancel()
        except Exception:
            pass
        c.close()


def run_case(title, prefetch, n=40, fast=0.005, slow=0.15, budget=6.0):
    print(f'\n--- {title} ---')
    reset()
    publish(n)
    r, u = stats()
    print(f'  发送 {n} 条（ready={r} unacked={u}）')

    w_fast = Worker('快消费者', fast, prefetch, budget)
    w_slow = Worker('慢消费者', slow, prefetch, budget)
    w_fast.start(); w_slow.start()
    w_fast.join(); w_slow.join()

    r, u = stats()
    total = w_fast.count + w_slow.count
    print(f'  快消费者处理: {w_fast.count:3d} 条')
    print(f'  慢消费者处理: {w_slow.count:3d} 条')
    if total:
        print(f'  快慢比: {w_fast.count / max(w_slow.count, 1):.1f} : 1'
              f'   （剩余 ready={r} unacked={u}）')
    return w_fast.count, w_slow.count


print('=' * 72)
print('公平性实验：两个消费者，快的处理 5ms/条，慢的 150ms/条，跑 6 秒')
print('=' * 72)

run_case('A. 不设 prefetch（默认无上限）', prefetch=None)
run_case('B. prefetch_count=1', prefetch=1)
run_case('C. prefetch_count=10', prefetch=10)

print()
print('=' * 72)
print('吞吐实验：prefetch 取值对吞吐的影响（单消费者，处理 1ms/条）')
print('=' * 72)
print(f'{"prefetch":>10}{"处理条数":>12}{"耗时(ms)":>12}{"条/秒":>12}')

for pf in (1, 5, 20, 100, 0):
    reset()
    publish(300)
    label = '无限' if pf == 0 else str(pf)
    c = pika.BlockingConnection(PARAMS)
    ch = c.channel()
    ch.queue_declare(queue=Q, durable=True)
    if pf:
        ch.basic_qos(prefetch_count=pf)
    t0 = time.time()
    cnt = 0
    for m, props, body in ch.consume(queue=Q, auto_ack=False, inactivity_timeout=1.0):
        if m is None:
            break
        ch.basic_ack(delivery_tag=m.delivery_tag)
        cnt += 1
        if cnt >= 300:
            break
    el = time.time() - t0
    c.close()
    print(f'{label:>10}{cnt:>12}{el * 1000:>12.0f}{cnt / el:>12.0f}')

print()
print('DONE')
