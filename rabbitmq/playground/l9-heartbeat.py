#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 9 实验 2：心跳协商机制（pika 1.4.4 实测 + 源码实证）
=========================================================
目的：回答"心跳值到底由谁决定"，并澄清一个与常见中文教程相反的事实。

背景与坑（本课真实踩坑记录）：
  1. pika 把协商结果放在 conn._impl._heartbeat_checker._send_interval
     （不是 _interval、不是 params.heartbeat）。params.heartbeat 只是【请求值】。
  2. _send_interval = 协商超时 / 2（符合 AMQP 规范：心跳帧每 timeout/2 秒发一次）
  3. rabbitmqctl list_connections 【不支持】heartbeat 列（报 Info key(s)
     heartbeat are not supported），服务端视角须用 HTTP API，
     且该 API 返回的 timeout 字段才是协商结果（heartbeat 字段恒为 None）。

⭐ 核心发现（与主流中文教程相反）：
  常见说法："协商取两端较小值，客户端只能调小不能调大"（此说法源自
  RabbitMQ 官方文档对 **Java/.NET/Erlang 官方客户端**的描述）。
  但 **pika 1.4.4 实测并非如此**：_tune_heartbeat_timeout 的实现是
      if client_value is None: timeout = server_value
      else:                     timeout = client_value
  即【客户端指定了值就无条件优先】，可以调大到超过服务端建议值。
  实测：服务端 heartbeat=60，客户端请求 600 → 协商结果 600（未被压缩）。

  教学结论：心跳最终值取决于【客户端库的实现】，不能一概而论。
  生产上不要依赖"服务端会帮我兜底"的假设，客户端要显式配置合理值。

运行：python3 l9-heartbeat.py
"""
import subprocess
import sys

import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')


def negotiated(hb):
    """建连接并返回协商后的心跳超时（秒）。

    取数方式经实测确认：
      协商值 = conn._impl._heartbeat_checker._send_interval * 2
      _send_interval 是心跳【发送间隔】= timeout / 2
    """
    conn = pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=CRED, heartbeat=hb))
    hc = conn._impl._heartbeat_checker
    if hc is None:
        conn.close()
        return 0
    interval = getattr(hc, '_send_interval', 0) or 0
    timeout = getattr(hc, '_timeout', None)
    conn.close()
    # 优先用 _timeout（就是协商超时），否则由发送间隔反推
    if timeout:
        return timeout
    return interval * 2


def server_view():
    """从服务端 HTTP API 读取各连接的 timeout（协商结果）"""
    r = subprocess.run(
        ['curl', '-s', '-u', 'learn:learn123',
         'http://localhost:15672/api/connections'],
        capture_output=True, text=True, timeout=30)
    try:
        import json
        data = json.loads(r.stdout)
        return [(c.get('name'), c.get('timeout')) for c in data]
    except Exception:
        return None


def main():
    print("=" * 74)
    print("课 9 实验 2：心跳协商机制（pika %s）" % pika.__version__)
    print("=" * 74)

    print("\n【A】pika 客户端视角：请求值 → 协商结果")
    print("")
    print("| 客户端请求 heartbeat | 发送间隔 _send_interval | 协商超时 |")
    print("|----------------------|------------------------|----------|")
    for hb in [0, 15, 30, 60, 120, 600]:
        conn = pika.BlockingConnection(pika.ConnectionParameters(
            host=HOST, port=PORT, credentials=CRED, heartbeat=hb))
        hc = conn._impl._heartbeat_checker
        if hc is None:
            si, to = None, 0
        else:
            si = getattr(hc, '_send_interval', None)
            to = getattr(hc, '_timeout', 0) or 0
        conn.close()
        print("| %d | %s | %s |" % (hb, si, to))

    print("\n【B】服务端视角（HTTP API 的 timeout 字段）")
    print("")
    print("| 连接 | 服务端记录的 timeout |")
    print("|------|----------------------|")
    rows = server_view()
    if rows is None:
        print("| （读取失败；容器内无 curl，需在宿主执行） | - |")
    elif not rows:
        print("| （当前无存活连接） | - |")
    else:
        for name, to in rows:
            print("| %s | %s |" % (name, to))

    print("\n【C】服务端配置基线")
    r = subprocess.run(
        ['docker', 'exec', 'rabbitmq-learn', 'rabbitmqctl', 'environment'],
        capture_output=True, text=True, timeout=60)
    for line in r.stdout.splitlines():
        if 'heartbeat' in line and 'aten' not in line:
            print("  %s" % line.strip())

    print("\n" + "=" * 74)
    print("⭐ 结论")
    print("=" * 74)
    print("1. 心跳帧发送间隔 = 协商超时 / 2（实测 30→15、600→300，符合规范）")
    print("2. pika 1.4.4 的协商算法是【客户端值优先】，不是'取较小值'")
    print("   源码：if client_value is None: server_value else: client_value")
    print("3. 因此客户端请求 600 时，服务端 60 的默认值【不会】把它压下来")
    print("4. 官方文档说的'取较小值'针对的是 Java/.NET/Erlang 官方客户端，")
    print("   pika 是社区客户端，行为不同——不要拿官方说法套所有客户端")
    print("5. 生产建议：显式配置心跳（5~20 秒官方推荐区间），不要依赖默认值，")
    print("   更不要假设'服务端会帮我兜底'")
    print("")
    print("⚠️ 另外两个实测坑：")
    print("   - rabbitmqctl list_connections 不支持 heartbeat 列")
    print("   - HTTP API 的 connections 里 heartbeat 字段恒为 None，看 timeout")
    return 0


if __name__ == '__main__':
    sys.exit(main())
