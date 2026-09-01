#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 10 实验 12：流控阻塞的严格验证（发布者视角）
==================================================
l10-flow-control.py 的遗留问题：
  内存告警已触发（Memory alarm on node ...），但 publish 未被阻塞（0.00s 成功）。

合理怀疑：blocked 通知是 broker【主动推送】给连接的，而
  - 告警触发时，我的连接还没建（先告警、后建连接）
  - 或连接已建但 blocked 帧尚未到达客户端，publish 就已发出
两种情况都会导致"看起来没被阻塞"。

本实验改用【严格时序】：
  1. 先建连接 + 声明队列（此时无告警）
  2. 再触发内存告警
  3. 等待并确认客户端收到 Connection.Blocked
  4. 然后 publish，测量是否被挂起
  5. 解除告警，确认收到 Connection.Unblocked
  6. 务必恢复原水位（0.6）

这样能准确回答："告警期间，发布者到底会不会被阻塞？"

⚠️ 安全：仍采用调低水位的软触发，不压内存；结束时恢复原值。
"""
import subprocess
import sys
import time

import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')
ORIG_MEM = '0.6'
Q = 'l10.flow.strict'

events = []


def ctl(*args, timeout=60):
    r = subprocess.run(['docker', 'exec', 'rabbitmq-learn', 'rabbitmqctl'] + list(args),
                       capture_output=True, text=True, timeout=timeout)
    return (r.stdout or '') + (r.stderr or '')


def conn_of(blocked_timeout=10):
    return pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=blocked_timeout))


def pump(conn, seconds):
    """驱动事件循环，让 blocked/unblocked 帧有机会被处理"""
    end = time.time() + seconds
    while time.time() < end:
        try:
            conn.process_data_events(time_limit=0.3)
        except Exception:
            break


def main():
    print("=" * 74)
    print("课 10 实验 12：流控阻塞的严格验证")
    print("=" * 74)

    # 1. 先建连接（无告警状态）
    conn = conn_of(blocked_timeout=10)
    conn.add_on_connection_blocked_callback(
        lambda c, m: events.append(('BLOCKED', time.time())))
    conn.add_on_connection_unblocked_callback(
        lambda c, m: events.append(('UNBLOCKED', time.time())))
    ch = conn.channel()
    try:
        ch.queue_delete(queue=Q)
    except Exception:
        pass
    ch.queue_declare(queue=Q, durable=True)
    print("\n【1】连接已建立（此时无告警）")

    # 2. 触发告警
    print("\n【2】触发内存告警（设水位为 0.000001）")
    ctl('set_vm_memory_high_watermark', '0.000001')
    time.sleep(2)
    pump(conn, 2)
    print("  已触发。当前客户端事件：%s" % [e[0] for e in events])

    # 3. 告警期间发布
    print("\n【3】告警期间发布消息（blocked_connection_timeout=10s）")
    t0 = time.time()
    result = 'unknown'
    try:
        ch.basic_publish(exchange='', routing_key=Q, body=b'under-alarm',
                         properties=pika.BasicProperties(delivery_mode=2))
        result = 'publish 返回成功'
    except Exception as e:
        result = '%s: %s' % (type(e).__name__, str(e)[:120])
    dur = time.time() - t0
    print("  结果：%s" % result)
    print("  耗时：%.2f s" % dur)
    if dur > 1:
        print("  ⚠️ publish 被【挂起】了 %.1f 秒 → 阻塞确实生效" % dur)
    else:
        print("  ⚠️ publish 立即返回 → 未观察到阻塞")

    # 4. 解除告警
    print("\n【4】解除告警（恢复水位 0.6）")
    ctl('set_vm_memory_high_watermark', ORIG_MEM)
    time.sleep(2)
    pump(conn, 3)
    print("  客户端事件序列：%s" % [e[0] for e in events])

    # 5. 恢复后再发一条，确认正常
    print("\n【5】恢复后再次发布（应正常）")
    try:
        t0 = time.time()
        ch.basic_publish(exchange='', routing_key=Q, body=b'after-recovery',
                         properties=pika.BasicProperties(delivery_mode=2))
        print("  成功，耗时 %.2f s" % (time.time() - t0))
    except Exception as e:
        print("  异常：%s" % str(e)[:120])

    print("\n" + "=" * 74)
    print("结论")
    print("=" * 74)
    print("事件序列：%s" % [(e[0], round(e[1] - events[0][1], 2)) for e in events]
          if events else "（未收到任何 blocked/unblocked 事件）")
    print("")
    print("判断依据：")
    print("  - 若收到 BLOCKED 且 publish 被挂起 → 阻塞机制生效")
    print("  - 若未收到 BLOCKED → 说明本环境/客户端下 blocked 通知未送达，")
    print("    或告警未传播到该连接；如实记录，不套用文档结论")

    # 清理
    try:
        ch.queue_delete(queue=Q)
    except Exception:
        pass
    try:
        conn.close()
    except Exception:
        pass

    # 最终确认水位已恢复
    out = ctl('status')
    for line in out.splitlines():
        if 'watermark setting' in line.lower():
            print("\n最终水位：%s" % line.strip())
    return 0


if __name__ == '__main__':
    sys.exit(main())
