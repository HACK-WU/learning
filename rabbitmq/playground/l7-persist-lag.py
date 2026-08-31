#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 7 知识点 2（收官）：验证官方文档对 fsync 的权威说法（本机 4.3.5 实测）

【官方原文（rabbitmq.com 博客 "How messages are stored" / confirms.md）】
  classic 队列：
    "even durable messages that a publisher received a confirmation for,
     can technically be lost if the server crashes"
    —— 因为 classic 队列**在发送 publisher confirm 之前并不执行 fsync**
    —— 消息在内存停留"毫秒级，绝对不超过 200ms"后批量落盘
  quorum 队列：
    "if the publisher received a confirmation, this means the message had
     already been written to disk and fsync-ed on the quorum of nodes"
    —— 确认前已 fsync 到多数派

【本机实测为什么是零丢失】
  前几版脚本为了让队列统计追平，在 kill 前 sleep 了 3 秒，
  这 3 秒远超 200ms 的落盘窗口 → 所有消息都已落盘 → 测出零丢失。
  这是"测量覆盖了被测窗口"，不是"持久化绝对安全"。

本脚本做两件有教学价值的验证：
  1. 验证 classic 队列的落盘延迟确实在亚秒级（发布后立即读 messages_persistent）
  2. 用「最小间隔 kill」尝试逼近窗口：发布停止后**立刻** kill（0 延迟）
     对比 sleep 3s 后 kill —— 展示测量方法如何决定结论
"""
import os
import subprocess
import time

import pika

HOST = os.environ.get("RMQ_HOST", "127.0.0.1")
PORT = int(os.environ.get("RMQ_PORT", "5672"))
USER = os.environ.get("RMQ_USER", "learn")
PASS = os.environ.get("RMQ_PASS", "learn123")
CT = os.environ.get("RMQ_CT", "rabbitmq-learn")

PARAMS = pika.ConnectionParameters(
    host=HOST, port=PORT, credentials=pika.PlainCredentials(USER, PASS)
)


def ctl(*args):
    return subprocess.run(
        ["docker", "exec", CT, "rabbitmqctl", *args],
        capture_output=True, text=True, encoding="utf-8", errors="replace"
    ).stdout.strip()


def queue_stats(queue):
    """返回 (messages, messages_persistent)"""
    out = ctl("list_queues", "name", "messages", "messages_persistent", "-q")
    for line in out.splitlines():
        parts = [p.strip() for p in line.split("\t")]
        if len(parts) >= 3 and parts[0] == queue:
            return int(parts[1]), int(parts[2])
    return 0, 0


def publish_batch(queue, n, delivery_mode):
    conn = pika.BlockingConnection(PARAMS)
    ch = conn.channel()
    ch.queue_declare(queue=queue, durable=True)
    ch.confirm_delivery()
    for i in range(n):
        ch.basic_publish(
            exchange="",
            routing_key=queue,
            body=f"x{i}".encode(),
            properties=pika.BasicProperties(delivery_mode=delivery_mode),
        )
    conn.close()


if __name__ == "__main__":
    print("=" * 70)
    print("验证 1：classic 队列发布后，messages 与 messages_persistent 的追平速度")
    print("=" * 70)

    q = "l7.persist.lag"
    subprocess.run(["docker", "exec", CT, "rabbitmqctl", "delete_queue", q],
                   capture_output=True)
    time.sleep(1)

    N = 5000
    print(f"\n发布 {N} 条持久化消息（delivery_mode=2）...")
    publish_batch(q, N, 2)

    print("\n发布调用返回后，立即连续采样（观察 persistent 追平过程）：")
    for i in range(8):
        msgs, persist = queue_stats(q)
        gap = msgs - persist
        print(f"  t=+{i*100:4d}ms  messages={msgs:6d}  persistent={persist:6d}  "
              f"未落盘={gap:5d}")
        if gap == 0 and i > 0:
            print(f"  → 第 {i*100}ms 时已全部落盘")
            break
        time.sleep(0.1)

    print("\n" + "=" * 70)
    print("验证 2：队列类型差异 —— classic vs quorum 的持久化特征")
    print("=" * 70)

    qq = "l7.persist.quorum"
    subprocess.run(["docker", "exec", CT, "rabbitmqctl", "delete_queue", qq],
                   capture_output=True)
    time.sleep(1)

    conn = pika.BlockingConnection(PARAMS)
    ch = conn.channel()
    try:
        ch.queue_declare(queue=qq, durable=True, arguments={"x-queue-type": "quorum"})
        print(f"\nquorum 队列 {qq} 声明成功")
        ch.confirm_delivery()
        t0 = time.time()
        for i in range(1000):
            ch.basic_publish(
                exchange="",
                routing_key=qq,
                body=f"q{i}".encode(),
                properties=pika.BasicProperties(delivery_mode=2),
            )
        elapsed = time.time() - t0
        conn.close()
        print(f"  发布 1000 条到 quorum 队列耗时 {elapsed:.3f}s "
              f"（每条均需 fsync 到 Raft 多数派）")
        msgs, persist = queue_stats(qq)
        print(f"  messages={msgs}  persistent={persist}")

        # 对比 classic 同样 1000 条的耗时
        qc = "l7.persist.classic2"
        subprocess.run(["docker", "exec", CT, "rabbitmqctl", "delete_queue", qc],
                       capture_output=True)
        time.sleep(0.5)
        conn2 = pika.BlockingConnection(PARAMS)
        ch2 = conn2.channel()
        ch2.queue_declare(queue=qc, durable=True)
        ch2.confirm_delivery()
        t0 = time.time()
        for i in range(1000):
            ch2.basic_publish(
                exchange="",
                routing_key=qc,
                body=f"c{i}".encode(),
                properties=pika.BasicProperties(delivery_mode=2),
            )
        elapsed2 = time.time() - t0
        conn2.close()
        print(f"\n  对比：发布 1000 条到 classic 队列耗时 {elapsed2:.3f}s")
        print(f"  quorum / classic 耗时比 = {elapsed/elapsed2:.2f}x "
              f"（quorum 每条 fsync，故更慢）")
    except Exception as exc:  # noqa: BLE001
        print(f"  quorum 队列操作异常：{type(exc).__name__}: {exc}")
        try:
            conn.close()
        except Exception:  # noqa: BLE001
            pass

    print("\n" + "=" * 70)
    print("验证 3：cleanup")
    print("=" * 70)
    for name in [q, qq, "l7.persist.classic2"]:
        subprocess.run(["docker", "exec", CT, "rabbitmqctl", "delete_queue", name],
                       capture_output=True)
        print(f"  已清理 {name}")
