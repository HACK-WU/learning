#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 9 实验 1：连接与信道的真实开销
==================================
目的：用数据回答"为什么信道是轻量虚拟连接"。
对比三个维度：
  A. 建 N 个 Connection 的耗时
  B. 在 1 个 Connection 上开 N 个 Channel 的耗时
  C. 内存/资源视角：连接数上限配置

测量方法（吸取课 8 教训）：
  - 每个场景独立跑，避免相互干扰
  - 报告原始耗时，不做跨场景的"倍数"推断除非量级差异极大
"""
import time
import sys
import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')
N = 50


def make_conn():
    return pika.BlockingConnection(
        pika.ConnectionParameters(host=HOST, port=PORT, credentials=CRED,
                                  heartbeat=600, blocked_connection_timeout=300))


def scenario_a(n=N):
    """A：建 n 个独立 Connection"""
    t0 = time.perf_counter()
    conns = []
    for i in range(n):
        c = make_conn()
        c.channel()   # 每个连接至少开一个信道才能用
        conns.append(c)
    t1 = time.perf_counter()
    for c in conns:
        try:
            c.close()
        except Exception:
            pass
    return (t1 - t0) * 1000, len(conns)


def scenario_b(n=N):
    """B：1 个 Connection 上开 n 个 Channel"""
    conn = make_conn()
    t0 = time.perf_counter()
    chs = []
    for i in range(n):
        chs.append(conn.channel())
    t1 = time.perf_counter()
    for ch in chs:
        try:
            ch.close()
        except Exception:
            pass
    conn.close()
    return (t1 - t0) * 1000, len(chs)


def main():
    print("=" * 72)
    print("课 9 实验 1：连接 vs 信道的创建开销（N=%d）" % N)
    print("=" * 72)

    try:
        probe = make_conn()
        probe.close()
    except Exception as e:
        print("无法连接 broker：%s" % e)
        return 1

    # 预热：先跑一轮小的，排除首次连接（TCP/握手/认证缓存）的冷启动影响
    print("预热中（各跑 5 次，不计入结果）...")
    for _ in range(5):
        scenario_a(5)
        scenario_b(5)

    print("正式测量...")
    ta, na = scenario_a()
    tb, nb = scenario_b()

    print("")
    print("| 场景 | 数量 | 总耗时 | 单条平均 |")
    print("|------|------|--------|----------|")
    print("| A. 建 %d 个 Connection | %d | %.1f ms | %.2f ms/个 |" % (N, na, ta, ta / na))
    print("| B. 开 %d 个 Channel    | %d | %.1f ms | %.2f ms/个 |" % (N, nb, tb, tb / nb))
    print("")

    ratio = ta / tb if tb > 0 else 0
    print("比值：建连接是开信道的 %.1f 倍耗时" % ratio)
    print("")
    print("⚠️ 数据说明：Channel 的创建大部分是客户端侧的状态登记 + 一次")
    print("   channel.open 往返；Connection 则包含 TCP 握手 + AMQP 协议头 +")
    print("   START/START-OK/TUNE/TUNE-OK/OPEN/OPEN-OK 多轮往返 + 认证。")
    print("   二者不在同一量级，这就是'信道是轻量虚拟连接'的含义。")

    return 0


if __name__ == '__main__':
    sys.exit(main())
