#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
排查：为什么 t=2.5s 时，1 秒 TTL 的消息还没消失？

现象（l7-ttl-dlx.py 实测）：
  队列 x-message-ttl=3000，发两条：
    A: expiration=10000（消息级 10s）
    B: expiration=1000 （消息级 1s）
  预期：B 在 1 秒后过期 → t=2.5s 时深度应为 1
  实测：t=2.5s 时深度 = 2（B 没消失！）
       t=4.5s 时深度 = 0（两条同时消失）

【关键怀疑：RabbitMQ 的惰性过期（lazy expiration）】
  官方 TTL 文档明确指出：
    "RabbitMQ 只保证过期的消息不会**被投递给消费者**，
     但不保证会**立即**从队列中删除。"
  真正删除发生在：
    1. 消息到达队列头部时（队首过期才被移除/死信）
    2. 或者队列被"检查"时（如 basic.get、消费、策略应用）
  → 若 B 排在 A 后面，且 A 未过期，B 虽然已过期却**不会被立即移除**，
    要等到它成为队首才被处理。这叫「队首阻塞式过期」。

【本脚本验证】
  对照组 1：只发 B（1s TTL）单独一条 → 它就在队首，应立即过期
  对照组 2：先发 A（10s）再发 B（1s）→ B 在 A 后面，验证队首阻塞
  对照组 3：用 basic.get 主动触发检查，看是否立即清掉已过期的 B
"""
import os
import time

import pika

HOST = os.environ.get("RMQ_HOST", "127.0.0.1")
PORT = int(os.environ.get("RMQ_PORT", "5672"))
USER = os.environ.get("RMQ_USER", "learn")
PASS = os.environ.get("RMQ_PASS", "learn123")

PARAMS = pika.ConnectionParameters(
    host=HOST, port=PORT, credentials=pika.PlainCredentials(USER, PASS)
)


def conn():
    return pika.BlockingConnection(PARAMS)


def depth(q):
    c = conn()
    ch = c.channel()
    try:
        r = ch.queue_declare(queue=q, durable=True, passive=True)
        n = r.method.message_count
    except Exception:  # noqa: BLE001
        n = -1
    c.close()
    return n


def sep(t):
    print("\n" + "=" * 70)
    print(f"  {t}")
    print("=" * 70)


def cleanup(*qs):
    import subprocess
    for q in qs:
        subprocess.run(["docker", "exec", "rabbitmq-learn",
                        "rabbitmqctl", "delete_queue", q],
                       capture_output=True)


# ---------------- 对照 1：单条 1 秒 TTL（它自己就是队首）----------------
def case_single():
    sep("对照 1：队列 TTL=10s，只发一条 expiration=1000 的消息（它即队首）")
    q = "l7.lazy.single"
    cleanup(q)
    c = conn(); ch = c.channel()
    ch.queue_declare(queue=q, durable=True, arguments={"x-message-ttl": 10000})
    ch.basic_publish(exchange="", routing_key=q, body=b"single-1s",
                     properties=pika.BasicProperties(
                         delivery_mode=2, expiration="1000"))
    ch.close(); c.close()
    print(f"  t=0.3s  深度={depth(q)}（期望 1）")
    time.sleep(1.5)
    print(f"  t=1.8s  深度={depth(q)}（1s TTL 已过，队首 → 期望 0）")
    cleanup(q)


# ---------------- 对照 2：长 TTL 在前，短 TTL 在后（队首阻塞）----------------
def case_blocked():
    sep("对照 2：先发 A(10s) 再发 B(1s) —— B 排在 A 后面（验证队首阻塞）")
    q = "l7.lazy.blocked"
    cleanup(q)
    c = conn(); ch = c.channel()
    ch.queue_declare(queue=q, durable=True, arguments={"x-message-ttl": 10000})
    ch.basic_publish(exchange="", routing_key=q, body=b"A-10s",
                     properties=pika.BasicProperties(
                         delivery_mode=2, expiration="10000"))
    ch.basic_publish(exchange="", routing_key=q, body=b"B-1s",
                     properties=pika.BasicProperties(
                         delivery_mode=2, expiration="1000"))
    ch.close(); c.close()
    print(f"  t=0.3s  深度={depth(q)}（期望 2）")
    time.sleep(1.5)
    print(f"  t=1.8s  深度={depth(q)}（B 的 1s 已过但排在 A 后 → 期望仍为 2）")
    time.sleep(1.5)
    print(f"  t=3.3s  深度={depth(q)}（期望仍为 2）")
    cleanup(q)


# ---------------- 对照 3：用 basic.get 主动触发检查 ----------------
def case_get_trigger():
    sep("对照 3：B 已过期但被 A 挡住 —— 用 basic.get 主动触发清理")
    q = "l7.lazy.get"
    cleanup(q)
    c = conn(); ch = c.channel()
    ch.queue_declare(queue=q, durable=True, arguments={"x-message-ttl": 10000})
    ch.basic_publish(exchange="", routing_key=q, body=b"A-10s",
                     properties=pika.BasicProperties(
                         delivery_mode=2, expiration="10000"))
    ch.basic_publish(exchange="", routing_key=q, body=b"B-1s",
                     properties=pika.BasicProperties(
                         delivery_mode=2, expiration="1000"))
    ch.close(); c.close()
    print(f"  t=0.3s  深度={depth(q)}（期望 2）")
    time.sleep(1.5)
    print(f"  t=1.8s  深度={depth(q)}（B 已过期，但被 A 挡住）")

    # 主动 basic.get 取出队首 A，看看取出后 B 是否被清理
    c = conn(); ch = c.channel()
    m1, p1, b1 = ch.basic_get(queue=q, auto_ack=True)
    print(f"  basic.get 取到：{b1.decode() if b1 else None}")
    ch.close(); c.close()
    time.sleep(0.3)
    print(f"  取出 A 后 深度={depth(q)}（B 到队首且已过期 → 期望 0）")
    cleanup(q)


# ---------------- 对照 4：短 TTL 在前，长 TTL 在后 ----------------
def case_reversed():
    sep("对照 4：先发 B(1s) 再发 A(10s) —— 短的在队首会怎样")
    q = "l7.lazy.rev"
    cleanup(q)
    c = conn(); ch = c.channel()
    ch.queue_declare(queue=q, durable=True, arguments={"x-message-ttl": 10000})
    ch.basic_publish(exchange="", routing_key=q, body=b"B-1s",
                     properties=pika.BasicProperties(
                         delivery_mode=2, expiration="1000"))
    ch.basic_publish(exchange="", routing_key=q, body=b"A-10s",
                     properties=pika.BasicProperties(
                         delivery_mode=2, expiration="10000"))
    ch.close(); c.close()
    print(f"  t=0.3s  深度={depth(q)}（期望 2）")
    time.sleep(1.5)
    print(f"  t=1.8s  深度={depth(q)}（B 在队首且已过期 → 期望 1）")
    time.sleep(1.5)
    print(f"  t=3.3s  深度={depth(q)}（期望 1，A 未到期）")
    cleanup(q)


if __name__ == "__main__":
    case_single()
    case_blocked()
    case_get_trigger()
    case_reversed()
    print("\n" + "=" * 70)
    print("  结论：RabbitMQ 的 TTL 是「惰性过期」—— 只有消息到达队首时才被移除")
    print("        排在后面的过期消息会被前面的消息阻塞，直到轮到它")
    print("=" * 70)
