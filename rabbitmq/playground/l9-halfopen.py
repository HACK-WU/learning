#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 9 实验 5：两种断线方式的感知时延对比（★本课最重要）
========================================================
课 7 方法学教训：验证"断线"不能用温和方式，否则测不出真实行为。

两种断线：
  A. 优雅断开（rabbitmqctl close_all_connections）
     → 服务端主动发 Connection.Close 帧，客户端【立即】感知
     → l9-reconnect.py 已验证：瞬间捕获 ConnectionClosedByBroker

  B. 半开连接（真实宕机 / 网络中断 / 拔网线）
     → 客户端【收不到任何帧】，TCP 仍认为连接正常
     → 只能靠【心跳超时】发现：等待 2 × heartbeat 秒
     → 这是最危险的场景，也是"消息莫名其妙不消费"的根因

本实验用 iptables 在容器内 DROP 掉已建立的 AMQP 连接包，
模拟网络中断（不发 RST，形成真正的半开连接），测量感知时延。

⚠️ 说明：若在容器内无法执行 iptables（权限/无该命令），脚本会
   明确报告降级原因，并改用理论值 + 心跳配置推算，不编造数据。

运行：python3 l9-halfopen.py
"""
import subprocess
import sys
import threading
import time

import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')
QUEUE = 'l9.halfopen.probe'
HEARTBEAT = 10          # 心跳 10 秒 → 理论感知 20 秒


def docker_exec(cmd, timeout=60):
    r = subprocess.run(['docker', 'exec', 'rabbitmq-learn'] + cmd,
                       capture_output=True, text=True, timeout=timeout)
    return r.returncode, (r.stdout or '') + (r.stderr or '')


def check_iptables():
    code, out = docker_exec(['sh', '-c', 'command -v iptables || echo NO_IPTABLES'])
    ok = 'NO_IPTABLES' not in out and code == 0
    return ok, out.strip()


def main():
    print("=" * 74)
    print("课 9 实验 5：半开连接的感知时延（heartbeat=%ds）" % HEARTBEAT)
    print("=" * 74)

    ok, info = check_iptables()
    print("\n【0】环境探测：容器内 iptables 可用性")
    print("  %s" % (("可用：%s" % info) if ok else ("不可用：%s" % info)))

    # 准备队列
    conn = pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=CRED, heartbeat=HEARTBEAT))
    ch = conn.channel()
    ch.queue_declare(queue=QUEUE, durable=True)
    ch.queue_purge(QUEUE)
    print("\n【1】已建立长连接（heartbeat=%d 秒），准备模拟断网" % HEARTBEAT)

    detected_at = {'t': None, 'err': None}

    def watcher():
        """持续消费，记录发现断线的时刻"""
        t0 = time.time()
        try:
            for method, props, body in ch.consume(QUEUE, auto_ack=True,
                                                  inactivity_timeout=1):
                if detected_at['t'] is None and time.time() - t0 > 0:
                    pass
        except Exception as e:
            detected_at['t'] = time.time()
            detected_at['err'] = '%s: %s' % (type(e).__name__, e)

    wt = threading.Thread(target=watcher, daemon=True)
    wt.start()
    time.sleep(2)

    if not ok:
        print("\n【降级】容器无 iptables，无法制造真实半开连接。")
        print("  改用可执行的替代验证：测量【心跳配置 → 理论感知时延】")
        print("")
        print("| heartbeat | 心跳帧间隔 | 理论感知时延（2×timeout） |")
        print("|-----------|------------|--------------------------|")
        for hb in [5, 10, 20, 30, 60]:
            print("| %ds | %.1fs | %ds |" % (hb, hb / 2, hb * 2))
        print("")
        print("  ★ 关键：heartbeat=60（服务端默认）时，断网后最长要等")
        print("    【120 秒】客户端才发现连接已死。这段时间内消息完全不消费，")
        print("    而运维看到的却是'消费者进程还在、连接还在'。")
        print("  → 这就是生产上必须把心跳调到 5~20 秒的原因。")
        conn.close()
        try:
            c = pika.BlockingConnection(pika.ConnectionParameters(
                host=HOST, port=PORT, credentials=CRED, heartbeat=60))
            c.channel().queue_delete(queue=QUEUE)
            c.close()
        except Exception:
            pass
        return 0

    print("\n【2】执行 iptables DROP（模拟网络中断，不发 RST）")
    code, out = docker_exec(['sh', '-c',
                             'iptables -A INPUT -p tcp --sport 5672 -j DROP; '
                             'iptables -A OUTPUT -p tcp --dport 5672 -j DROP'])
    print("  iptables 返回 code=%s out=%s" % (code, out.strip()[:100]))
    t_drop = time.time()

    print("\n【3】等待客户端感知（最长 %d 秒）..." % (HEARTBEAT * 3))
    deadline = t_drop + HEARTBEAT * 3
    while time.time() < deadline and detected_at['t'] is None:
        time.sleep(0.5)

    print("\n【4】清理 iptables 规则")
    docker_exec(['sh', '-c',
                 'iptables -D INPUT -p tcp --sport 5672 -j DROP 2>/dev/null; '
                 'iptables -D OUTPUT -p tcp --dport 5672 -j DROP 2>/dev/null'])

    print("\n" + "=" * 74)
    print("实验结果")
    print("=" * 74)
    if detected_at['t']:
        delay = detected_at['t'] - t_drop
        print("感知时延：%.1f 秒（理论值 %d 秒）" % (delay, HEARTBEAT * 2))
        print("异常类型：%s" % detected_at['err'])
    else:
        print("在 %d 秒内未感知到断线" % (HEARTBEAT * 3))

    try:
        conn.close()
    except Exception:
        pass
    try:
        c = pika.BlockingConnection(pika.ConnectionParameters(
            host=HOST, port=PORT, credentials=CRED, heartbeat=60))
        c.channel().queue_delete(queue=QUEUE)
        c.close()
    except Exception:
        pass
    return 0


if __name__ == '__main__':
    sys.exit(main())
