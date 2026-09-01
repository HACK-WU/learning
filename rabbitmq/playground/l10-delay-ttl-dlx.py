#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 10 实验 1：延迟消息的两条路 —— TTL+DLX vs 延迟插件
======================================================
本环境（4.3.5）【没有】rabbitmq_delayed_message_exchange 插件（已确认：
rabbitmq-plugins list 中不存在该插件）。因此：

  路线一 TTL+DLX：可实测（本课重点）
  路线二 延迟插件：说明原理，标注"本环境未安装、无法实测"

另外 4.3 新增【quorum 队列原生延迟重试】，单独在 l10-delayed-retry.py 实测。

TTL+DLX 延迟队列的结构：
    publisher → 主交换机 → 延迟队列（设 x-message-ttl + x-dead-letter-exchange）
                                ↓ TTL 到期后自动死信
                            目标交换机 → 业务队列 → consumer

⚠️ 核心坑（本课要证明）：
  RabbitMQ 的 per-message TTL 是【惰性检查】的——只对队首消息生效。
  如果队首消息 TTL=30s、后面紧跟一条 TTL=5s 的消息，
  后者不会在 5 秒后到期，必须等队首的 30 秒过去。
  这是 TTL+DLX 方案的【顺序陷阱】。

本实验实测量：
  A. 正常场景：单条消息 TTL=5s，验证约 5 秒后出现在业务队列
  B. 顺序陷阱：先发 TTL=30s，再发 TTL=5s，验证后者被前者【堵住】
  C. 队列级 TTL vs 消息级 TTL 的差异
"""
import sys
import time

import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')

DELAY_EX = 'l10.delay.ex'
TARGET_EX = 'l10.target.ex'
DELAY_Q = 'l10.delay.q'
BUSY_Q = 'l10.busy.q'


def conn_of():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=300))


def setup():
    """搭建 TTL+DLX 延迟队列拓扑"""
    c = conn_of()
    ch = c.channel()
    # 清理
    for q in (DELAY_Q, BUSY_Q):
        try:
            ch.queue_delete(queue=q)
        except Exception:
            pass
    for ex in (DELAY_EX, TARGET_EX):
        try:
            ch.exchange_delete(exchange=ex)
        except Exception:
            pass

    ch.exchange_declare(exchange=DELAY_EX, exchange_type='direct', durable=True)
    ch.exchange_declare(exchange=TARGET_EX, exchange_type='direct', durable=True)

    # 延迟队列：消息过期后死信到目标交换机
    ch.queue_declare(
        queue=DELAY_Q, durable=True,
        arguments={
            'x-dead-letter-exchange': TARGET_EX,
            'x-dead-letter-routing-key': 'go',
        })
    ch.queue_bind(queue=DELAY_Q, exchange=DELAY_EX, routing_key='delay')

    # 业务队列
    ch.queue_declare(queue=BUSY_Q, durable=True)
    ch.queue_bind(queue=BUSY_Q, exchange=TARGET_EX, routing_key='go')
    c.close()


def depth(queue):
    c = conn_of()
    ch = c.channel()
    n = ch.queue_declare(queue=queue, durable=True, passive=True).method.message_count
    c.close()
    return n


def purge_all():
    c = conn_of()
    ch = c.channel()
    for q in (DELAY_Q, BUSY_Q):
        try:
            ch.queue_purge(queue=q)
        except Exception:
            pass
    c.close()


def publish(delay_ms, body, queue=DELAY_Q, exchange=DELAY_EX, rk='delay'):
    c = conn_of()
    ch = c.channel()
    ch.basic_publish(
        exchange=exchange, routing_key=rk, body=body,
        properties=pika.BasicProperties(
            delivery_mode=2,
            expiration=str(delay_ms),      # 消息级 TTL（毫秒）
        ))
    c.close()


def wait_until(queue, expect, timeout=60):
    """等待队列深度达到 expect，返回实际耗时（秒）"""
    t0 = time.time()
    while time.time() - t0 < timeout:
        if depth(queue) >= expect:
            return time.time() - t0
        time.sleep(0.2)
    return None


def cleanup():
    c = conn_of()
    ch = c.channel()
    for q in (DELAY_Q, BUSY_Q):
        try:
            ch.queue_delete(queue=q)
        except Exception:
            pass
    for ex in (DELAY_EX, TARGET_EX):
        try:
            ch.exchange_delete(exchange=ex)
        except Exception:
            pass
    c.close()


def main():
    print("=" * 74)
    print("课 10 实验 1：延迟消息（TTL + DLX）")
    print("=" * 74)
    setup()

    # A. 单条延迟
    print("\n【A】单条消息 TTL=5000ms，测量多久出现在业务队列")
    purge_all()
    publish(5000, b'A-delay-5s')
    t = wait_until(BUSY_Q, 1, timeout=30)
    print("  业务队列耗时：%s（期望 ≈ 5.0s）" % (
        "%.2f s" % t if t else "超时未出现"))

    # B. 顺序陷阱（本课核心）
    print("\n【B】顺序陷阱：先发 TTL=20s，再发 TTL=3s")
    purge_all()
    t0 = time.time()
    publish(20000, b'B-slow-20s')      # 队首，20 秒
    time.sleep(0.5)
    publish(3000, b'B-fast-3s')        # 第二条，3 秒
    print("  已发送两条（间隔 0.5s），等待第二条到达业务队列...")

    t_fast = None
    t_slow = None
    deadline = time.time() + 40
    while time.time() < deadline:
        d = depth(BUSY_Q)
        if d >= 1 and t_fast is None:
            t_fast = time.time() - t0
        if d >= 2:
            t_slow = time.time() - t0
            break
        time.sleep(0.2)

    print("")
    print("| 消息 | 设定 TTL | 实际到达业务队列 | 判定 |")
    print("|------|----------|------------------|------|")
    if t_fast:
        print("| B-fast-3s | 3s | %.2f s | %s |" % (
            t_fast, "正常" if t_fast < 6 else "⚠️ 被队首堵住"))
    else:
        print("| B-fast-3s | 3s | 超时 | ⚠️ 未到达 |")
    if t_slow:
        print("| B-slow-20s | 20s | %.2f s | - |" % t_slow)

    print("")
    print("  ★ 若 B-fast-3s 的实际耗时接近 20s 而非 3s，即证明：")
    print("    per-message TTL 只对【队首】生效，后面的短 TTL 消息会被")
    print("    前面的长 TTL 消息堵住。这就是 TTL+DLX 的顺序陷阱。")

    # C. 队列级 TTL
    print("\n【C】队列级 TTL（x-message-ttl）与消息级 TTL 的差异")
    print("  队列级 TTL 作用于整个队列，不存在'队首堵塞'问题，")
    print("  但代价是【整个队列共用一个 TTL】，无法按消息定制延迟。")
    print("  → 这是为什么实际工程里常按延迟档位建多个延迟队列")
    print("    （如 delay.5s / delay.30s / delay.5m）")

    cleanup()
    print("\n已清理拓扑")
    return 0


if __name__ == '__main__':
    sys.exit(main())
