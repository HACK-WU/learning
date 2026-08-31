#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 7 排查：为什么 B 组「交换机非持久化」重启后消息还在？

两种可能假设：
  H1：容器 restart 太快，broker 根本没真正重启（优雅关闭又立刻起来，内存态被保留？）
      —— 不成立：restart 会杀进程，内存态必丢。
  H2：非持久化交换机在重启后确实消失了，但**消息并不依赖交换机存活**：
      消息存在队列里，绑定关系随交换机消失而消失，但已入队的消息不受影响。
      → 这个假设与实测一致！消息数仍是 1。
  H3：交换机根本没消失（durable=False 的交换机也被持久化了？）

实测方案：
  1. 精确检查重启后 l7.ex.noex 是否还在（上面 check 已显示 True，需复核）
  2. 检查绑定是否还在
  3. 关键补测：重启后**再往 B 组交换机发消息**，看还能不能路由（交换机没了则消息丢失）
"""
import os
import subprocess

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


print("=== 1. 重启后交换机清单（看 l7.ex.noex 是否还在）===")
all_ex = ctl("list_exchanges", "name", "-q").splitlines()
for name in ["l7.ex.all", "l7.ex.noex", "l7.ex.rmsg"]:
    print(f"  {name:14s} 存在={name in [x.strip() for x in all_ex]}")

print("\n=== 2. 重启后绑定关系（看非持久化交换机的绑定是否还在）===")
bindings = ctl("list_bindings", "source_name", "destination_name", "-q")
for line in bindings.splitlines():
    if "l7." in line:
        print(f"  {line}")

print("\n=== 3. 关键补测：重启后向 B 组交换机再发一条，看能否路由 ===")
try:
    conn = pika.BlockingConnection(PARAMS)
    ch = conn.channel()
    # 不重新声明交换机，直接用已存在的（若交换机已消失，这里会 404 NOT_FOUND）
    ch.queue_declare(queue="l7.q.noex", durable=True)
    ch.basic_publish(
        exchange="l7.ex.noex",
        routing_key="rk",
        body=b"after-restart",
        properties=pika.BasicProperties(delivery_mode=2),
    )
    conn.close()
    print("  发布未报错（说明交换机仍在）")
except Exception as exc:  # noqa: BLE001
    print(f"  发布异常：{type(exc).__name__}: {exc}")

print("\n=== 4. 检查 B 组队列当前消息数 ===")
qs = ctl("list_queues", "name", "messages", "-q")
for line in qs.splitlines():
    parts = line.split("\t")
    if len(parts) == 2 and parts[0].strip().startswith("l7."):
        print(f"  {parts[0].strip():14s} messages={parts[1].strip()}")

print("\n=== 5. 直接看交换机是否真的消失（用 HTTP API 查）===")
import urllib.request
import json
import base64

auth = base64.b64encode(f"{USER}:{PASS}".encode()).decode()
req = urllib.request.Request("http://127.0.0.1:15672/api/exchanges/%2F")
req.add_header("Authorization", f"Basic {auth}")
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.load(resp)
    for e in data:
        if e.get("name", "").startswith("l7."):
            print(f"  {e['name']:14s} type={e.get('type')} durable={e.get('durable')} "
                  f"auto_delete={e.get('auto_delete')}")
except Exception as exc:  # noqa: BLE001
    print(f"  API 异常：{exc}")
