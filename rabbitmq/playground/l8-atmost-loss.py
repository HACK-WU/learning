#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8 知识点 1 补充实测：at-most-once 下崩溃到底丢几条？
=========================================================
背景（异常发现）：主实验 A 组投递 5 条、消费者只"处理"了 2 条就崩溃，
队列剩余却是 0 条（预期 3 条）。怀疑是 auto_ack=True 且默认 prefetch 无上限，
broker 一次性把队列全部推空 → 5 条全部自动确认删除。

本脚本验证三件事：
  V1: auto_ack=True 且无 prefetch 时，消费者进程实际收到几条？（是否一次推空）
  V2: 崩溃时丢失的是"正在处理的 1 条"还是"已推送未处理的所有条"？
  V3: 加上 prefetch_count=1 能否救回来？（课 6 已证：不能，prefetch 对 auto_ack 无效）

预期（依据课 6 结论）：
  V1: 收到 5 条（一次推空）
  V2: 丢失 5 条（全部）
  V3: 加了 prefetch 依然一次推空 → 丢失 5 条
"""
import time
import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')


def conn():
    return pika.BlockingConnection(
        pika.ConnectionParameters(host=HOST, port=PORT, credentials=CRED,
                                  heartbeat=600, blocked_connection_timeout=300))


def depth(q):
    c = conn()
    ch = c.channel()
    try:
        n = ch.queue_declare(queue=q, durable=True, passive=True).method.message_count
    except Exception:
        n = -1
    c.close()
    return n


def reset(q):
    c = conn()
    ch = c.channel()
    try:
        ch.queue_delete(queue=q)
    except Exception:
        pass
    c.close()


TOTAL = 5


def run_case(label, qname, prefetch=None, crash_at=2):
    """跑一组：投递 TOTAL 条 → 消费者收到 crash_at 条时崩溃 → 看丢了几个"""
    reset(qname)
    c = conn()
    ch = c.channel()
    ch.queue_declare(queue=qname, durable=True)
    for i in range(1, TOTAL + 1):
        ch.basic_publish(exchange='', routing_key=qname, body=f'm{i}'.encode(),
                         properties=pika.BasicProperties(delivery_mode=2))
    c.close()

    got = []

    def on_msg(ch, method, properties, body):
        got.append(body.decode())
        if len(got) >= crash_at:
            raise SystemExit(0)

    c = conn()
    ch = c.channel()
    if prefetch:
        ch.basic_qos(prefetch_count=prefetch)
    ch.basic_consume(queue=qname, on_message_callback=on_msg, auto_ack=True)
    try:
        ch.start_consuming()
    except (SystemExit, KeyboardInterrupt):
        pass
    except Exception:
        pass
    finally:
        try:
            c.close()
        except Exception:
            pass

    time.sleep(1.2)
    remain = depth(qname)
    lost = TOTAL - remain
    print(f"\n  [{label}]")
    print(f"    投递 {TOTAL} 条，消费者进程实际收到 {len(got)} 条时崩溃")
    print(f"    崩溃后队列剩余 = {remain} 条")
    print(f"    >>> 本次崩溃共丢失 {lost} 条（不是 {crash_at} 条）")
    return {'got': len(got), 'remain': remain, 'lost': lost}


print("=" * 74)
print("验证：at-most-once 崩溃时到底丢几条？")
print("=" * 74)

r1 = run_case("V1/V2 无 prefetch（默认）", 'l8.crash.noprefetch', prefetch=None)
r2 = run_case("V3   prefetch_count=1", 'l8.crash.prefetch1', prefetch=1)

print("\n" + "=" * 74)
print("结论")
print("=" * 74)
print(f"  无 prefetch : 进程收到 {r1['got']} 条 / 崩溃丢失 {r1['lost']} 条")
print(f"  prefetch=1  : 进程收到 {r2['got']} 条 / 崩溃丢失 {r2['lost']} 条")
if r1['got'] == TOTAL:
    print(f"\n  ✅ 证实 V1：auto_ack=True 时 broker 一次性推空整个队列（收到 {TOTAL} 条）")
    print(f"  ✅ 证实 V2：崩溃丢失的是『已推送但未处理的所有消息』= {r1['lost']} 条，")
    print(f"             而不是『正在处理的那 1 条』")
else:
    print(f"\n  ⚠️ V1 未证实：只收到 {r1['got']} 条，非一次推空")
if r2['lost'] == r1['lost'] and r1['got'] == TOTAL:
    print(f"  ✅ 证实 V3：prefetch=1 对 auto_ack 无效，丢失条数不变（课 6 结论重现）")
elif r2['lost'] < r1['lost']:
    print(f"  ⚠️ V3 与预期相反：prefetch=1 居然救回了 {r1['lost'] - r2['lost']} 条，需复查")
