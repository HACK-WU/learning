#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 10 实验 9：优先级队列
=========================
知识点：
  - 队列声明 x-max-priority（1~255，推荐 <=10）
  - 消息发布时设 priority 属性
  - 4.3 起 quorum 队列支持【32 级严格优先级】（4.0~4.2 只支持 2 级相对）

⚠️ 重要前提（官方文档）：
  优先级只有当【消费者跟不上、队列有积压】时才有意义。
  如果消费者一直空闲，消息一到就被取走，优先级【完全不起作用】。

本实验实测量：
  A. x-max-priority 的取值边界（0/1/10/255/256）
  B. 有积压时，高优先级是否先被消费
  C. 无积压（消费者空闲）时，优先级是否"失效"
  D. classic 队列的优先级表现
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


def scenario_a():
    """A：x-max-priority 取值边界"""
    print("\n【A】x-max-priority 取值边界（classic 队列）")
    print("")
    print("| x-max-priority | 声明结果 |")
    print("|----------------|----------|")
    c = conn_of()
    ch = c.channel()
    for v in [0, 1, 10, 255, 256]:
        qn = 'l10.prio.bound.%s' % v
        try:
            ch.queue_delete(queue=qn)
        except Exception:
            pass
        try:
            ch.queue_declare(queue=qn, durable=True,
                             arguments={'x-max-priority': v})
            print("| %s | ✅ 接受 |" % v)
            ch.queue_delete(queue=qn)
        except Exception as e:
            msg = str(e).replace('\n', ' ')
            print("| %s | ❌ 拒绝：%s |" % (v, msg[:55]))
    c.close()


def scenario_b(qtype, maxp, label):
    """B：有积压时，高优先级是否先出"""
    qn = 'l10.prio.backlog'
    c = conn_of()
    ch = c.channel()
    try:
        ch.queue_delete(queue=qn)
    except Exception:
        pass
    args = {'x-max-priority': maxp}
    if qtype:
        args['x-queue-type'] = qtype
    ch.queue_declare(queue=qn, durable=True, arguments=args)

    # 先堆积 10 条：优先级 0,1,2,...,9（乱序发布）
    order = [0, 5, 2, 9, 1, 7, 3, 8, 4, 6]
    for p in order:
        ch.basic_publish(exchange='', routing_key=qn,
                         body=('P%d' % p).encode(),
                         properties=pika.BasicProperties(
                             delivery_mode=2, priority=p))
    time.sleep(1)

    # 现在开始消费，看取出顺序
    got = []
    for _ in range(10):
        m = ch.basic_get(qn, auto_ack=True)
        if m[0] is None:
            break
        got.append(int(m[2].decode()[1:]))

    print("\n【%s】积压后消费顺序（%s）" % (label, "x-max-priority=%s" % maxp))
    print("")
    print("  发布顺序：%s" % order)
    print("  消费顺序：%s" % got)
    sorted_desc = got == sorted(got, reverse=True)
    print("  是否严格降序（高优先级先出）：%s" % ("✅ 是" if sorted_desc else "❌ 否"))

    try:
        ch.queue_delete(queue=qn)
    except Exception:
        pass
    c.close()
    return got


def scenario_c():
    """C：消费者空闲（无积压）时，优先级是否失效"""
    qn = 'l10.prio.idle'
    c = conn_of()
    ch = c.channel()
    try:
        ch.queue_delete(queue=qn)
    except Exception:
        pass
    ch.queue_declare(queue=qn, durable=True,
                     arguments={'x-queue-type': 'quorum', 'x-max-priority': 10})

    print("\n【C】无积压场景：发一条立刻取一条（消费者永远空闲）")
    got = []
    for p in [1, 9, 2, 8, 3]:
        ch.basic_publish(exchange='', routing_key=qn, body=('P%d' % p).encode(),
                         properties=pika.BasicProperties(
                             delivery_mode=2, priority=p))
        time.sleep(0.4)
        m = ch.basic_get(qn, auto_ack=True)
        if m[0] is not None:
            got.append(int(m[2].decode()[1:]))

    print("  发布优先级：%s" % [1, 9, 2, 8, 3])
    print("  实际取出：  %s" % got)
    same = got == [1, 9, 2, 8, 3]
    print("  是否与发布顺序一致（优先级未起作用）：%s" % ("✅ 是" if same else "❌ 否"))
    print("")
    print("  ★ 这印证官方文档的结论：消费者跟得上时，优先级【不起作用】。")
    print("    消息一到就被取走，队列里永远只有 0 或 1 条，无从排序。")

    try:
        ch.queue_delete(queue=qn)
    except Exception:
        pass
    c.close()


def main():
    print("=" * 74)
    print("课 10 实验 9：优先级队列")
    print("=" * 74)
    print("环境：RabbitMQ 4.3.5 / pika %s" % pika.__version__)

    scenario_a()
    scenario_b('quorum', 10, 'B1 quorum 队列')
    scenario_b(None, 10, 'B2 classic 队列')
    scenario_c()

    print("\n" + "=" * 74)
    print("要点")
    print("=" * 74)
    print("1. 优先级只在【有积压】时才有意义，消费者空闲时完全不起作用")
    print("2. 高 x-max-priority 有 CPU 代价，官方推荐不要超过 10")
    print("3. 优先级会【破坏顺序性】——课 8 讲的顺序保证在优先级队列上不成立")
    print("4. 4.3 起 quorum 队列支持 32 级严格优先级（4.0~4.2 仅 2 级相对）")
    return 0


if __name__ == '__main__':
    sys.exit(main())
