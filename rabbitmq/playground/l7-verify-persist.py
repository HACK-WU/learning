#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 7 知识点 1 + 2 的权威验证：持久化消息计数与落盘延迟

【踩坑记录（三种取数方式实测对比）】
  1. Management API 单队列接口 /api/queues/{vhost}/{name}
     → 默认返回**不含** messages / messages_persistent，
       实测只有 name/durable/type/state/arguments 等基础字段
  2. 加 ?columns=messages,messages_persistent
     → 单队列接口**不支持**该参数，返回 0
  3. 列表接口 /api/queues/{vhost}?columns=...
     → 能返回 messages，但 messages_persistent 缺失
  4. ✅ rabbitmqctl list_queues name messages messages_persistent
     → 实测输出 "l7.col.probe\\t2\\t1"，权威可靠，最终采用

本脚本验证：
  1. delivery_mode=2 的消息计入 messages_persistent
  2. delivery_mode=1 的消息不计入 messages_persistent
  3. classic 队列发布返回后 persistent 已在亚秒级追平（批量落盘）
"""
import json
import os
import subprocess
import sys
import time
import urllib.request
import base64

import pika

HOST = os.environ.get("RMQ_HOST", "127.0.0.1")
PORT = int(os.environ.get("RMQ_PORT", "5672"))
USER = os.environ.get("RMQ_USER", "learn")
PASS = os.environ.get("RMQ_PASS", "learn123")
API = os.environ.get("RMQ_API", "http://127.0.0.1:15672/api")

AUTH = base64.b64encode(f"{USER}:{PASS}".encode()).decode()


def api_get(path):
    req = urllib.request.Request(f"{API}{path}")
    req.add_header("Authorization", f"Basic {AUTH}")
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.load(resp)


def stats(queue):
    """
    取队列统计（权威来源：rabbitmqctl list_queues）

    【踩坑记录】
      Management API 在本环境不可靠：
        - 单队列接口 /api/queues/{vhost}/{name} 默认返回**不含**统计字段
        - 加 ?columns=messages,messages_persistent 后返回 0（不支持该参数）
        - 列表接口 /api/queues/{vhost}?columns=... 能返回 messages，
          但 messages_persistent 缺失
      而 rabbitmqctl list_queues name messages messages_persistent **实测可用**：
        输出 "l7.col.probe\\t2\\t1" = 2 条消息、其中 1 条持久化。
      故本函数改用 rabbitmqctl。
    """
    try:
        out = subprocess.run(
            ["docker", "exec", "rabbitmq-learn", "rabbitmqctl",
             "list_queues", "name", "messages", "messages_persistent", "-q"],
            capture_output=True, text=True, encoding="utf-8", errors="replace"
        ).stdout
        for line in out.splitlines():
            parts = [p.strip() for p in line.split("\t")]
            if len(parts) == 3 and parts[0] == queue:
                return int(parts[1]), int(parts[2])
        return -1, -1
    except Exception as exc:  # noqa: BLE001
        print(f"    [stats 异常] {exc}")
        return -1, -1


def conn():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=pika.PlainCredentials(USER, PASS)))


if __name__ == "__main__":
    print("=" * 70)
    print("知识点 1：delivery_mode 决定消息是否计入 messages_persistent")
    print("=" * 70)

    c = conn(); ch = c.channel()
    ch.queue_declare(queue="l7.vp.p2", durable=True)
    ch.queue_declare(queue="l7.vp.p1", durable=True)
    ch.confirm_delivery()
    ch.basic_publish(exchange="", routing_key="l7.vp.p2", body=b"persistent",
                     properties=pika.BasicProperties(delivery_mode=2))
    ch.basic_publish(exchange="", routing_key="l7.vp.p1", body=b"transient",
                     properties=pika.BasicProperties(delivery_mode=1))
    c.close()
    time.sleep(0.5)

    m2, p2 = stats("l7.vp.p2")
    m1, p1 = stats("l7.vp.p1")
    print(f"\n  delivery_mode=2 队列：messages={m2}  persistent={p2}  "
          f"→ {'✅ 已持久化' if p2 == 1 else '❌'}")
    print(f"  delivery_mode=1 队列：messages={m1}  persistent={p1}  "
          f"→ {'✅ 未计入持久化' if p1 == 0 else '❌'}")

    print("\n" + "=" * 70)
    print("知识点 2：classic 队列的落盘延迟（messages_persistent 追平速度）")
    print("=" * 70)

    N = 3000
    c = conn(); ch = c.channel()
    ch.queue_declare(queue="l7.vp.lag", durable=True)
    ch.confirm_delivery()
    t0 = time.time()
    for i in range(N):
        ch.basic_publish(exchange="", routing_key="l7.vp.lag", body=f"x{i}".encode(),
                         properties=pika.BasicProperties(delivery_mode=2))
    pub_elapsed = time.time() - t0
    c.close()

    print(f"\n  发布 {N} 条耗时 {pub_elapsed:.3f}s（pika 逐条同步 confirm）")
    print("  发布返回后立即采样（观察 persistent 追平）：")
    for i in range(6):
        m, p = stats("l7.vp.lag")
        gap = m - p
        print(f"    t=+{i*100:4d}ms  messages={m:5d}  persistent={p:5d}  未落盘={gap:4d}")
        if gap == 0 and i > 0:
            print(f"    → 第 {i*100}ms 已全部落盘")
            break
        time.sleep(0.1)

    print("\n" + "=" * 70)
    print("清理")
    print("=" * 70)
    import subprocess
    for q in ["l7.vp.p2", "l7.vp.p1", "l7.vp.lag"]:
        subprocess.run(["docker", "exec", "rabbitmq-learn",
                        "rabbitmqctl", "delete_queue", q], capture_output=True)
        print(f"  已删 {q}")
