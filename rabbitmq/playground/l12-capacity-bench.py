#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 12 实验 2：容量规划实测——消息大小与吞吐的关系
======================================================
知识点 3「生产落地清单」的容量规划部分。

官方文档只会告诉你"RabbitMQ 不擅长大消息"，但多大算大、
代价有多大，必须自己测。

本实验实测（在三节点集群的 quorum 队列上）：
  - 不同消息体大小（1KB / 10KB / 100KB / 1MB）下的发布吞吐
  - 每条消息的平均耗时
  - 换算成"每秒多少 MB"

目的：让"别用 RabbitMQ 传大消息"从一句口号变成可量化的判断，
     并给出 claim-check（大对象存外部、消息只传引用）的决策依据。

同时记录本环境的吞吐基线，说明"网上的吞吐数字为什么不能直接抄"。
"""
import statistics
import subprocess
import sys
import time

import pika

PORT = 5681
CRED = pika.PlainCredentials('learn', 'learn123')
NODE = 'rmq1'


def conn():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost', port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=120, socket_timeout=120))


def mem_mb():
    """读取节点内存占用（MB）"""
    r = subprocess.run(
        ['docker', 'exec', NODE, 'rabbitmqctl', 'status'],
        capture_output=True, text=True, timeout=90)
    for ln in (r.stdout or '').splitlines():
        if 'memory,' in ln or 'memory:' in ln:
            try:
                # 形如：{memory,[{total,{erlang,1234567}},...
                import re
                nums = re.findall(r'\d{6,}', ln)
                if nums:
                    return int(nums[0]) / 1024 / 1024
            except Exception:
                pass
    return None


def bench(size_bytes, n=500):
    """测指定消息大小下的发布吞吐"""
    q = 'l12.bench.%d' % size_bytes
    c = conn()
    ch = c.channel()
    try:
        ch.queue_delete(queue=q)
    except Exception:
        pass
    time.sleep(1)
    ch.queue_declare(queue=q, durable=True,
                     arguments={'x-queue-type': 'quorum'})
    time.sleep(2)
    ch.confirm_delivery()

    payload = b'x' * size_bytes

    # 预热 20 条（避免首条的连接建立/队列初始化计入）
    for _ in range(20):
        ch.basic_publish(exchange='', routing_key=q, body=payload,
                         properties=pika.BasicProperties(delivery_mode=2))

    # 正式计时
    latencies = []
    t0 = time.time()
    for _ in range(n):
        s = time.time()
        ch.basic_publish(exchange='', routing_key=q, body=payload,
                         properties=pika.BasicProperties(delivery_mode=2))
        latencies.append((time.time() - s) * 1000)
    elapsed = time.time() - t0

    tps = n / elapsed if elapsed > 0 else 0
    mbps = (tps * size_bytes) / (1024 * 1024)

    # 清理
    try:
        ch.queue_delete(queue=q)
    except Exception:
        pass
    c.close()

    return {
        'size': size_bytes,
        'n': n,
        'elapsed': elapsed,
        'tps': tps,
        'mbps': mbps,
        'avg_ms': statistics.mean(latencies) if latencies else 0,
        'p95_ms': (statistics.quantiles(latencies, n=20)[18]
                   if len(latencies) > 20 else max(latencies or [0])),
    }


def main():
    print("=" * 74)
    print("课 12 实验 2：消息大小 vs 吞吐（容量规划实测）")
    print("=" * 74)
    print("集群：rmq1/rmq2/rmq3（4.3.5）｜ quorum 队列 + publisher confirms")
    print("每组 500 条，先预热 20 条")
    print("")
    print("注意：这是单客户端、跨 docker 网络的 WSL/Windows 环境，")
    print("      绝对值不代表生产性能；要看的是【相对趋势】。")

    results = []
    for size in (1024, 10 * 1024, 100 * 1024, 1024 * 1024):
        label = ('%d KB' % (size // 1024)) if size < 1024 * 1024 else '1 MB'
        print("\n  正在测试 %s ..." % label, flush=True)
        r = bench(size, n=500)
        results.append(r)
        print("    吞吐 %8.1f 条/秒   带宽 %7.2f MB/s   平均 %6.2f ms" % (
            r['tps'], r['mbps'], r['avg_ms']))

    print("\n" + "=" * 74)
    print("结果汇总")
    print("=" * 74)
    print("")
    print("| 消息大小 | 吞吐（条/秒） | 带宽（MB/s） | 平均延迟（ms） | P95（ms） |")
    print("|----------|--------------|--------------|----------------|-----------|")
    for r in results:
        label = ('%d KB' % (r['size'] // 1024)) if r['size'] < 1024 * 1024 else '1 MB'
        print("| %s | %8.1f | %7.2f | %6.2f | %6.2f |" % (
            label, r['tps'], r['mbps'], r['avg_ms'], r['p95_ms']))

    # 关键洞察：条/秒 与 大小的关系
    print("")
    base = results[0]
    print("相对 1KB 的基准：")
    print("")
    print("| 消息大小 | 条/秒 相对值 | 带宽 相对值 |")
    print("|----------|-------------|-------------|")
    for r in results:
        label = ('%d KB' % (r['size'] // 1024)) if r['size'] < 1024 * 1024 else '1 MB'
        print("| %s | %5.2fx | %5.2fx |" % (
            label, base['tps'] / r['tps'] if r['tps'] else 0,
            r['mbps'] / base['mbps'] if base['mbps'] else 0))

    print("")
    print("=" * 74)
    print("怎么读这张表")
    print("=" * 74)
    print("1. 消息变大时，【条/秒】会掉，但【带宽 MB/s】通常会涨——")
    print("   瓶颈不在字节数，而在【每条消息的固定开销】（Raft 复制、fsync）")
    print("2. 当带宽不再随消息变大而增长时，说明已到网络/磁盘上限")
    print("3. 1MB 消息对 quorum 队列是重负担：每条都要复制到 3 个节点并 fsync")
    print("")
    print("工程结论：")
    print("  - 消息体尽量控制在 KB 级")
    print("  - 超过 100KB 考虑 claim-check：")
    print("    大对象放对象存储（S3/COS），消息里只传引用（URL/key）")
    print("  - 网上的吞吐数字（如'百万 TPS'）多为 stream 类型 + 多客户端 +")
    print("    大消息批量，与本实测场景不同，不可直接抄")

    m = mem_mb()
    if m:
        print("")
        print("节点 %s 当前内存占用：%.1f MB" % (NODE, m))
    return 0


if __name__ == '__main__':
    sys.exit(main())
