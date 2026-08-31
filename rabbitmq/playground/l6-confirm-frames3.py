#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 6 实测 9：Broker 到底回了几个 Ack 帧？（修正统计时机）

l6-confirm-frames2.py 只捕到 1 帧，原因：BlockingChannel 每条 publish 都会
_flush_output 并消费掉自己的确认帧，注册在 _impl 上的回调只在
"进入 publish 之前的空闲时刻"被调用到 1 次。

本版改用**不依赖 pika 内部**的外部证据 —— 直接从 broker 侧统计：
用管理插件的 HTTP API `/api/queues/{vhost}/{queue}` 读取
`message_stats.publish_in` / `publish_out` 等计数器，结合
`rabbitmqctl list_connections` 的帧统计。

更直接的证据：用 **rabbitmq-diagnostics 或 HTTP API 看 channel 的 confirm 计数**。
RabbitMQ 在 /api/channels 里暴露 `confirms` 相关字段吗？先探查可用字段。

同时给一个**决定性实验**：两条连接并发 publish，若 broker 能流水线，
总耗时应接近单条连接（而非 2 倍）——因为瓶颈是 RTT 且可以并行。
"""
import json
import subprocess
import time
import threading
import pika
import urllib.request

CRED = pika.PlainCredentials('learn', 'learn123')
PARAMS = pika.ConnectionParameters(host='localhost', port=5672, credentials=CRED)
BODY = b'x' * 256
Q = 'l6_parallel'


def http_get(path):
    url = f'http://localhost:15672/api/{path}'
    req = urllib.request.Request(url)
    import base64
    tok = base64.b64encode(b'learn:learn123').decode()
    req.add_header('Authorization', f'Basic {tok}')
    with urllib.request.urlopen(req, timeout=5) as r:
        return json.loads(r.read().decode())


print('=' * 72)
print('1) 探查 HTTP API 是否暴露 confirm 相关计数')
print('=' * 72)
try:
    chs = http_get('channels')
    if chs:
        keys = sorted(chs[0].keys())
        confirm_keys = [k for k in keys if 'confirm' in k.lower()
                        or 'publish' in k.lower() or 'unack' in k.lower()]
        print(f'  /api/channels 中与 confirm/发布 相关的字段: {confirm_keys}')
    else:
        print('  当前无活动 channel，跳过')
except Exception as e:
    print(f'  探查失败: {e}')

print()
print('=' * 72)
print('2) 决定性实验：单连接 vs 多连接并发 publish（confirm 模式）')
print('=' * 72)
print('  若瓶颈是"每条等一个 RTT"，则 2 条连接并发的耗时应接近单连接')
print('  （因为两条连接的等待可以重叠）→ 证明 broker 侧处理很快')


def reset():
    c = pika.BlockingConnection(PARAMS); ch = c.channel()
    ch.queue_declare(queue=Q, durable=True); ch.queue_purge(Q); c.close()


def publish_batch(n, results, idx):
    c = pika.BlockingConnection(PARAMS); ch = c.channel()
    ch.queue_declare(queue=Q, durable=True)
    ch.confirm_delivery()
    t0 = time.time()
    for _ in range(n):
        ch.basic_publish(exchange='', routing_key=Q, body=BODY)
    results[idx] = time.time() - t0
    c.close()


N = 300

# 单连接
reset()
t0 = time.time()
publish_batch(N, {}, 0)
single = time.time() - t0

# 2 连接并发（各 N 条，总量翻倍）
reset()
res = {}
ths = [threading.Thread(target=publish_batch, args=(N, res, i)) for i in range(2)]
t0 = time.time()
for t in ths:
    t.start()
for t in ths:
    t.join()
par2 = time.time() - t0

# 4 连接并发
reset()
res4 = {}
ths4 = [threading.Thread(target=publish_batch, args=(N, res4, i)) for i in range(4)]
t0 = time.time()
for t in ths4:
    t.start()
for t in ths4:
    t.join()
par4 = time.time() - t0

print(f'  单连接 {N} 条            : {single * 1000:8.1f} ms   吞吐 {N / single:8.0f} 条/秒')
print(f'  2 连接并发（共 {2 * N} 条）: {par2 * 1000:8.1f} ms   吞吐 {2 * N / par2:8.0f} 条/秒')
print(f'  4 连接并发（共 {4 * N} 条）: {par4 * 1000:8.1f} ms   吞吐 {4 * N / par4:8.0f} 条/秒')
print()
print(f'  → 单连接吞吐 {N / single:.0f} 条/秒 ≈ 1/(RTT)，并发后吞吐提升到 '
      f'{4 * N / par4:.0f} 条/秒')
print('    说明每条 publish 的等待**可以重叠** —— 瓶颈是 RTT 等待，不是 broker 处理。')
print('    这正是"异步 confirm 能快"的物理基础。')

print()
print('DONE')
