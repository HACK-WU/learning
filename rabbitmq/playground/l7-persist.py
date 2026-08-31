#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 7 知识点 1：三层持久化 —— 逐层验证「缺一层会怎样」

三个开关：
  1. exchange durable=True   交换机元数据是否活过重启
  2. queue    durable=True   队列元数据 + 内容是否活过重启
  3. message  delivery_mode=2  消息本身是否活过重启

验证矩阵（重启前后对照）：
  A. 三层全开          → 期望：交换机/队列/消息全在
  B. 交换机非持久化     → 期望：交换机消失 → 绑定消失 → 消息随之消失（即使队列和消息都持久化）
  C. 队列非持久化       → 期望：4.3 上直接 541 建不了（课 3/课 5 已知事实）
  D. 消息非持久化       → 期望：交换机队列都在，消息没了

注意：C 在 4.3 上无法直接测（durable=False + 非排他 = 541），
      故改为测「队列持久化但交换机不持久化」这个更隐蔽的坑。
"""
import os
import sys
import time
import subprocess

import pika

HOST = os.environ.get("RMQ_HOST", "127.0.0.1")
PORT = int(os.environ.get("RMQ_PORT", "5672"))
USER = os.environ.get("RMQ_USER", "learn")
PASS = os.environ.get("RMQ_PASS", "learn123")
CT = os.environ.get("RMQ_CT", "rabbitmq-learn")

CRED = pika.PlainCredentials(USER, PASS)
PARAMS = pika.ConnectionParameters(host=HOST, port=PORT, credentials=CRED)


def rabbitmqctl(*args):
    return subprocess.run(
        ["docker", "exec", CT, "rabbitmqctl", *args],
        capture_output=True, text=True, encoding="utf-8", errors="replace"
    ).stdout.strip()


def declare_and_publish(exchange, exchange_durable, queue, queue_durable,
                        delivery_mode, routing_key="rk"):
    """声明一组交换机/队列/绑定，并发布一条消息。返回连接。"""
    conn = pika.BlockingConnection(PARAMS)
    ch = conn.channel()
    ch.exchange_declare(
        exchange=exchange,
        exchange_type="direct",
        durable=exchange_durable,
    )
    ch.queue_declare(queue=queue, durable=queue_durable)
    ch.queue_bind(exchange=exchange, queue=queue, routing_key=routing_key)
    ch.basic_publish(
        exchange=exchange,
        routing_key=routing_key,
        body=f"payload-{queue}".encode(),
        properties=pika.BasicProperties(delivery_mode=delivery_mode),
    )
    return conn


def build(exchange, exchange_durable, queue, queue_durable, delivery_mode, label):
    print(f"\n{'='*72}")
    print(f"【{label}】exchange.durable={exchange_durable}  queue.durable={queue_durable}  "
          f"delivery_mode={delivery_mode}")
    print("=" * 72)
    try:
        conn = declare_and_publish(exchange, exchange_durable, queue,
                                   queue_durable, delivery_mode)
        conn.close()
    except Exception as exc:  # noqa: BLE001
        print(f"  构建阶段异常：{type(exc).__name__}: {exc}")
        return

    ex = rabbitmqctl("list_exchanges", "name", "-q").splitlines()
    qs = rabbitmqctl("list_queues", "name", "messages", "-q").splitlines()
    has_ex = exchange in [x.strip() for x in ex]
    q_msg = "0"
    for line in qs:
        parts = line.split("\t")
        if len(parts) == 2 and parts[0].strip() == queue:
            q_msg = parts[1].strip()
    print(f"  重启前：交换机存在={has_ex}  队列消息数={q_msg}")


def check(exchange, queue, label):
    ex = rabbitmqctl("list_exchanges", "name", "-q").splitlines()
    qs = rabbitmqctl("list_queues", "name", "messages", "-q").splitlines()
    has_ex = exchange in [x.strip() for x in ex]
    has_q = False
    q_msg = "不存在"
    for line in qs:
        parts = line.split("\t")
        if len(parts) == 2 and parts[0].strip() == queue:
            has_q = True
            q_msg = parts[1].strip()
    print(f"  重启后：交换机存在={has_ex}  队列存在={has_q}  队列消息数={q_msg}")
    return has_ex, has_q, q_msg


if __name__ == "__main__":
    phase = sys.argv[1] if len(sys.argv) > 1 else "build"

    groups = [
        # (交换机名, 交换机durable, 队列名, 队列durable, delivery_mode, 标签)
        ("l7.ex.all",  True,  "l7.q.all",  True, 2, "A 三层全开"),
        ("l7.ex.noex", False, "l7.q.noex", True, 2, "B 交换机非持久化（队列+消息都持久化）"),
        ("l7.ex.rmsg", True,  "l7.q.rmsg", True, 1, "D 消息非持久化（交换机+队列都持久化）"),
    ]

    if phase == "build":
        for ex, exd, q, qd, dm, label in groups:
            build(ex, exd, q, qd, dm, label)
        print("\n>>> 构建完成，现在重启容器，再运行：python l7-persist.py check")
    elif phase == "check":
        for ex, exd, q, qd, dm, label in groups:
            print(f"\n{'='*72}")
            print(f"【{label}】exchange.durable={exd}  queue.durable={qd}  delivery_mode={dm}")
            print("=" * 72)
            check(ex, q, label)
