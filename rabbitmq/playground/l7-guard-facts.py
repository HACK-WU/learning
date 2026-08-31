#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 7 守护脚本：守护两条本课实测发现、且极易被后续课程/实践推翻的硬事实

【守护事实 1】durable=False 的交换机在 4.3.5 上活过真实强制宕机
  背景：官方文档（AMQP concepts）称 transient exchange 不活过重启。
  实测：4.3.5 用 Khepri 存元数据（Raft 日志），所有元数据都落盘，
        故 l7.mini.transient(durable=False) 在 docker kill -s KILL 后依然存在。
  意义：后续课程若断言"transient 交换机重启必消失"，本脚本会报警。

【守护事实 2】delivery_mode 决定消息是否计入 messages_persistent
  实测：delivery_mode=2 → messages_persistent=1
        delivery_mode=1 → messages_persistent=0（队列仍在，消息数相同）
  意义：这是"队列持久化 ≠ 消息持久化"的量化证据。

【守护事实 3】TTL 惰性过期
  实测：短 TTL 消息排在长 TTL 消息后面时，不会按时消失（被队首阻塞）
  意义：防止后续误以为 TTL 到期即删除。
"""
import os
import subprocess
import sys
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

FAILURES = []


def ctl(*args):
    return subprocess.run(
        ["docker", "exec", CT, "rabbitmqctl", *args],
        capture_output=True, text=True, encoding="utf-8", errors="replace"
    ).stdout.strip()


def conn():
    return pika.BlockingConnection(PARAMS)


def exchange_exists(name):
    return name in [x.strip() for x in ctl("list_exchanges", "name", "-q").splitlines()]


def queue_stats(name):
    """返回 (messages, messages_persistent)"""
    for line in ctl("list_queues", "name", "messages",
                    "messages_persistent", "-q").splitlines():
        parts = [p.strip() for p in line.split("\t")]
        if len(parts) == 3 and parts[0] == name:
            return int(parts[1]), int(parts[2])
    return 0, 0


def assert_true(desc, cond, detail=""):
    if cond:
        print(f"  ✅ {desc}  {detail}")
    else:
        print(f"  ❌ {desc}  {detail}")
        FAILURES.append(desc)


# --------------------------------------------------------------- 事实 2
def guard_delivery_mode():
    print("\n【守护事实 2】delivery_mode 决定消息持久化")
    c = conn(); ch = c.channel()
    ch.queue_declare(queue="l7.guard.p2", durable=True)
    ch.queue_declare(queue="l7.guard.p1", durable=True)
    ch.confirm_delivery()
    ch.basic_publish(exchange="", routing_key="l7.guard.p2", body=b"persist",
                     properties=pika.BasicProperties(delivery_mode=2))
    ch.basic_publish(exchange="", routing_key="l7.guard.p1", body=b"transient",
                     properties=pika.BasicProperties(delivery_mode=1))
    ch.close(); c.close()
    time.sleep(0.5)

    m2, p2 = queue_stats("l7.guard.p2")
    m1, p1 = queue_stats("l7.guard.p1")
    assert_true("delivery_mode=2 计入 messages_persistent", p2 == 1,
                f"(messages={m2}, persistent={p2})")
    assert_true("delivery_mode=1 不计入 messages_persistent", p1 == 0,
                f"(messages={m1}, persistent={p1})")

    for q in ["l7.guard.p2", "l7.guard.p1"]:
        subprocess.run(["docker", "exec", CT, "rabbitmqctl", "delete_queue", q],
                       capture_output=True)


# --------------------------------------------------------------- 事实 3
def guard_lazy_ttl():
    print("\n【守护事实 3】TTL 惰性过期（短 TTL 被队首阻塞）")
    q = "l7.guard.lazy"
    subprocess.run(["docker", "exec", CT, "rabbitmqctl", "delete_queue", q],
                   capture_output=True)
    time.sleep(0.5)

    c = conn(); ch = c.channel()
    ch.queue_declare(queue=q, durable=True, arguments={"x-message-ttl": 10000})
    # A 长 TTL 在前，B 短 TTL 在后
    ch.basic_publish(exchange="", routing_key=q, body=b"A-10s",
                     properties=pika.BasicProperties(delivery_mode=2,
                                                     expiration="10000"))
    ch.basic_publish(exchange="", routing_key=q, body=b"B-1s",
                     properties=pika.BasicProperties(delivery_mode=2,
                                                     expiration="1000"))
    ch.close(); c.close()

    time.sleep(2.5)  # B 的 1 秒 TTL 早已过去
    m, _ = queue_stats(q)
    assert_true("短 TTL 消息被队首阻塞，未按时消失", m == 2,
                f"(2.5s 后队列深度={m}，期望 2)")

    subprocess.run(["docker", "exec", CT, "rabbitmqctl", "delete_queue", q],
                   capture_output=True)


# --------------------------------------------------------------- 事实 1
def guard_transient_exchange():
    """
    守护事实 1 需要真实宕机，会中断服务，故默认跳过。
    需要验证时：python l7-guard-facts.py --with-crash
    """
    print("\n【守护事实 1】transient 交换机活过真实宕机（需宕机，默认跳过）")
    print("  ⏭️  跳过。如需验证请执行：python l7-guard-facts.py --with-crash")


def guard_transient_exchange_crash():
    print("\n【守护事实 1】transient 交换机活过真实宕机（含 docker kill -s KILL）")
    for e in ["l7.guard.tr", "l7.guard.du"]:
        subprocess.run(["docker", "exec", "-e", f"RABBITMQADMIN_USERNAME={USER}",
                        "-e", f"RABBITMQADMIN_PASSWORD={PASS}", CT,
                        "rabbitmqadmin", "delete", "exchange",
                        "--name", e, "--non-interactive"], capture_output=True)

    c = conn(); ch = c.channel()
    ch.exchange_declare(exchange="l7.guard.tr", exchange_type="direct", durable=False)
    ch.exchange_declare(exchange="l7.guard.du", exchange_type="direct", durable=True)
    ch.close(); c.close()
    print("  已声明 l7.guard.tr(durable=False) 与 l7.guard.du(durable=True)")

    before_uptime = ctl("status").split("Uptime (seconds):")[-1].split()[0] \
        if "Uptime (seconds):" in ctl("status") else "?"

    print("  执行 docker kill -s KILL ...")
    subprocess.run(["docker", "kill", "-s", "KILL", CT], capture_output=True)
    time.sleep(2)
    subprocess.run(["docker", "start", CT], capture_output=True)
    for _ in range(120):
        if "Uptime" in ctl("status"):
            break
        time.sleep(1)
    time.sleep(5)

    after_uptime = ctl("status").split("Uptime (seconds):")[-1].split()[0] \
        if "Uptime (seconds):" in ctl("status") else "?"

    print(f"  宕机前 uptime={before_uptime}s  宕机后 uptime={after_uptime}s")

    tr = exchange_exists("l7.guard.tr")
    du = exchange_exists("l7.guard.du")
    assert_true("durable=True 交换机存活", du)
    assert_true("durable=False 交换机同样存活（4.3 Khepri 行为）", tr,
                "若此项为 False，说明版本行为已变化，需更新课 7 讲义")

    for e in ["l7.guard.tr", "l7.guard.du"]:
        subprocess.run(["docker", "exec", "-e", f"RABBITMQADMIN_USERNAME={USER}",
                        "-e", f"RABBITMQADMIN_PASSWORD={PASS}", CT,
                        "rabbitmqadmin", "delete", "exchange",
                        "--name", e, "--non-interactive"], capture_output=True)


if __name__ == "__main__":
    print("=" * 70)
    print("课 7 事实守护脚本")
    print("=" * 70)
    guard_delivery_mode()
    guard_lazy_ttl()
    if "--with-crash" in sys.argv:
        guard_transient_exchange_crash()
    else:
        guard_transient_exchange()

    print("\n" + "=" * 70)
    if FAILURES:
        print(f"❌ {len(FAILURES)} 项事实已被推翻，需更新讲义：")
        for f in FAILURES:
            print(f"   - {f}")
        sys.exit(1)
    print("✅ 全部守护事实仍然成立")
