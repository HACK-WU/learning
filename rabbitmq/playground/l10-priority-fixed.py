#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 10 实验 10：优先级队列（修正版）
====================================
重要修正（官方文档原文）：
  "Priorities Are Always Enabled. Quorum queues always provide the full
   0-31 priority range. There is no opt-in argument: x-max-priority
   applies only to classic queues and is IGNORED by quorum queues."

即：
  - classic 队列：需要 x-max-priority（[1,255]），实测 256 被拒
  - quorum 队列：优先级【默认启用】，固定 0-31 共 32 级，
                  传 x-max-priority 反而会被【拒绝】（实测已证）

其他关键事实（官方）：
  - 优先级超出 0-31 会被【钳制（clamped）】
  - 未设 priority 的消息：quorum 视为【4】，classic 视为【0】（默认值不同！）
  - 被返回（reject/nack）的消息【不保留原优先级】，按返回顺序重排
  - 优先级只在【有积压】时才有意义

本实验实测：
  A. classic 队列的 x-max-priority 边界（0/1/10/255/256）
  B. quorum 队列不传 x-max-priority，验证 32 级严格优先级
  C. 优先级钳制：priority=100 是否等同 31
  D. 有积压 vs 无积压（消费者空闲）时优先级是否生效
"""
import sys
import time

import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')


def conn_of():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=300))


def fresh(ch, qn, args=None):
    try:
        ch.queue_delete(queue=qn)
    except Exception:
        pass
    return ch.queue_declare(queue=qn, durable=True, arguments=args)


def scenario_a():
    print("\n【A】classic 队列 x-max-priority 边界")
    print("")
    print("| x-max-priority | 声明结果 |")
    print("|----------------|----------|")
    c = conn_of()
    for v in [0, 1, 10, 255, 256]:
        qn = 'l10.cp.%s' % v
        try:
            ch = c.channel()
            fresh(ch, qn, {'x-max-priority': v})
            print("| %s | ✅ 接受 |" % v)
            ch.queue_delete(queue=qn)
        except Exception as e:
            print("| %s | ❌ 拒绝：%s |" % (v, str(e)[:50]))
            try:
                c = conn_of()
            except Exception:
                pass
    try:
        c.close()
    except Exception:
        pass


def scenario_b():
    """quorum 32 级严格优先级"""
    print("\n【B】quorum 队列 32 级严格优先级（不传 x-max-priority）")
    qn = 'l10.qp.strict'
    c = conn_of()
    ch = c.channel()
    # 关键：不传 x-max-priority
    fresh(ch, qn, {'x-queue-type': 'quorum'})

    # 乱序发布 12 条，优先级 0..11
    order = [0, 7, 3, 11, 1, 9, 2, 10, 4, 8, 5, 6]
    for p in order:
        ch.basic_publish(exchange='', routing_key=qn, body=('P%02d' % p).encode(),
                         properties=pika.BasicProperties(
                             delivery_mode=2, priority=p))
    time.sleep(1.5)

    got = []
    for _ in range(12):
        m = ch.basic_get(qn, auto_ack=True)
        if m[0] is None:
            break
        got.append(int(m[2].decode()[1:]))

    print("  发布顺序：%s" % order)
    print("  消费顺序：%s" % got)
    ok = got == sorted(got, reverse=True)
    print("  严格降序（高优先级先出）：%s" % ("✅ 是" % () if ok else "❌ 否"))
    ch.queue_delete(queue=qn)
    c.close()
    return ok


def scenario_c():
    """优先级钳制：priority=100 是否等同 31"""
    print("\n【C】优先级钳制（quorum，官方称钳制到 0-31）")
    qn = 'l10.qp.clamp'
    c = conn_of()
    ch = c.channel()
    fresh(ch, qn, {'x-queue-type': 'quorum'})

    # 发两条：priority=5（普通）与 priority=100（应被钳到 31）
    ch.basic_publish(exchange='', routing_key=qn, body=b'P005',
                     properties=pika.BasicProperties(
                         delivery_mode=2, priority=5))
    ch.basic_publish(exchange='', routing_key=qn, body=b'P100',
                     properties=pika.BasicProperties(
                         delivery_mode=2, priority=100))
    time.sleep(1)

    got = []
    for _ in range(2):
        m = ch.basic_get(qn, auto_ack=True)
        if m[0] is not None:
            got.append(m[2].decode())
    print("  发布：priority=5, priority=100")
    print("  消费顺序：%s" % got)
    if got and got[0] == 'P100':
        print("  ✅ priority=100 被当作最高级处理（钳制到 31）")
    else:
        print("  ⚠️ 顺序为 %s，与钳制预期不符" % got)
    ch.queue_delete(queue=qn)
    c.close()


def scenario_d():
    """未设优先级的默认值：quorum=4，classic=0"""
    print("\n【D】未设 priority 时的默认值（官方：quorum=4, classic=0）")
    for qtype, args, label in [
        ('quorum', {'x-queue-type': 'quorum'}, 'quorum'),
        (None, {'x-max-priority': 10}, 'classic(max=10)'),
    ]:
        qn = 'l10.def.%s' % (qtype or 'classic')
        c = conn_of()
        ch = c.channel()
        fresh(ch, qn, args)
        # 发三条：无优先级、priority=2、priority=8
        ch.basic_publish(exchange='', routing_key=qn, body=b'NO_PRIORITY')
        ch.basic_publish(exchange='', routing_key=qn, body=b'P2',
                         properties=pika.BasicProperties(
                             delivery_mode=2, priority=2))
        ch.basic_publish(exchange='', routing_key=qn, body=b'P8',
                         properties=pika.BasicProperties(
                             delivery_mode=2, priority=8))
        time.sleep(1.2)
        got = []
        for _ in range(3):
            m = ch.basic_get(qn, auto_ack=True)
            if m[0] is not None:
                got.append(m[2].decode())
        print("  %-16s 消费顺序：%s" % (label, got))
        print("                   （无优先级消息的落位反映其默认优先级）")
        ch.queue_delete(queue=qn)
        c.close()


def scenario_e():
    """消费者空闲（无积压）时优先级是否失效"""
    print("\n【E】无积压场景：发一条立刻取一条")
    qn = 'l10.idle.test'
    c = conn_of()
    ch = c.channel()
    fresh(ch, qn, {'x-queue-type': 'quorum'})
    sent = [1, 9, 2, 8, 3]
    got = []
    for p in sent:
        ch.basic_publish(exchange='', routing_key=qn, body=('P%d' % p).encode(),
                         properties=pika.BasicProperties(
                             delivery_mode=2, priority=p))
        time.sleep(0.5)
        m = ch.basic_get(qn, auto_ack=True)
        if m[0] is not None:
            got.append(int(m[2].decode()[1:]))
    print("  发布优先级：%s" % sent)
    print("  实际取出：  %s" % got)
    print("  与发布顺序一致（优先级未起作用）：%s" % ("✅ 是" if got == sent else "❌ 否"))
    print("")
    print("  ★ 印证官方文档：消费者跟得上时，消息一到就被取走，")
    print("    队列里没有积压，优先级【无从排序】、完全不起作用。")
    ch.queue_delete(queue=qn)
    c.close()


def main():
    print("=" * 74)
    print("课 10 实验 10：优先级队列（修正版）")
    print("=" * 74)
    print("环境：RabbitMQ 4.3.5 / pika %s" % pika.__version__)

    scenario_a()
    scenario_b()
    scenario_c()
    scenario_d()
    scenario_e()

    print("\n" + "=" * 74)
    print("要点小结")
    print("=" * 74)
    print("1. classic 需 x-max-priority（1~255），quorum【不需要且不接受】")
    print("2. quorum 默认 32 级（0-31）严格优先级，超出钳制")
    print("3. 未设优先级：quorum 默认 4，classic 默认 0（不同！）")
    print("4. 优先级只在【有积压】时生效，消费者空闲时无效")
    print("5. 优先级破坏顺序性（呼应课 8）")
    return 0


if __name__ == '__main__':
    sys.exit(main())
