#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 10 实验 2：quorum 队列的原生延迟重试（RabbitMQ 4.3 新增）
=============================================================
4.3 为 quorum 队列引入原生延迟重试，配置参数：
    x-delayed-retry-type : disabled | all | failed | returned
    x-delayed-retry-min  : 最小延迟（毫秒）
    x-delayed-retry-max  : 最大延迟（毫秒，默认 = min）

延迟计算（线性退避）：
    delay = min(delayed_retry_min * delivery_count, delayed_retry_max)

例如 min=3000, max=12000：
    第 1 次返回 → 3s
    第 2 次返回 → 6s
    第 3 次返回 → 9s
    第 4 次及以后 → 12s（封顶）

⚠️ 关键前提（4.3 语义变更，与课 6/课 9 的旧结论直接相关）：
  4.3 起 quorum 队列区分两个计数器：
    acquired-count ：每次 requeue 都 +1
    delivery-count ：仅【投递失败】时才 +1
  而 delivery-limit（毒消息处理）只看 delivery-count。

  按官方文档的判定表：
    AMQP 0.9.1 basic.nack  → acquired-count +1，delivery-count 【不】+1
    AMQP 0.9.1 basic.reject → acquired-count +1，delivery-count +1
  即：**basic.nack 不计入 delivery-limit，可以无限次返回**。

  ⚠️ 这与课 6 记录的结论（"nack requeue 到 delivery-limit 后死信"）
     存在张力，必须以【本环境 4.3.5 的实测】为准。

本实验实测量：
  A. x-delayed-retry-type 各取值的效果
  B. 延迟是否随返回次数线性增长（min=3000, max=12000）
  C. nack 是否触发延迟（对比 reject）
"""
import sys
import time

import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')
Q = 'l10.retry.q'


def conn_of():
    return pika.BlockingConnection(pika.ConnectionParameters(
        host=HOST, port=PORT, credentials=CRED, heartbeat=600,
        blocked_connection_timeout=300))


def declare_q(retry_type='failed', rmin=3000, rmax=12000, delivery_limit=10):
    c = conn_of()
    ch = c.channel()
    try:
        ch.queue_delete(queue=Q)
    except Exception:
        pass
    ch.queue_declare(
        queue=Q, durable=True,
        arguments={
            'x-queue-type': 'quorum',
            'x-delayed-retry-type': retry_type,
            'x-delayed-retry-min': rmin,
            'x-delayed-retry-max': rmax,
            'x-delivery-limit': delivery_limit,
        })
    c.close()


def depth():
    c = conn_of()
    ch = c.channel()
    n = ch.queue_declare(queue=Q, durable=True, passive=True).method.message_count
    c.close()
    return n


def probe_args():
    """读取队列声明后的实际参数"""
    c = conn_of()
    ch = c.channel()
    # 用 passive 声明读回参数
    res = ch.queue_declare(queue=Q, durable=True, passive=True)
    c.close()
    return res.method.arguments if hasattr(res.method, 'arguments') else None


def publish(body):
    c = conn_of()
    ch = c.channel()
    ch.basic_publish(exchange='', routing_key=Q, body=body,
                     properties=pika.BasicProperties(delivery_mode=2))
    c.close()


def wait_ready(timeout=30):
    """等待消息变为 ready（延迟期间消息不可投递）"""
    t0 = time.time()
    while time.time() - t0 < timeout:
        c = conn_of()
        ch = c.channel()
        try:
            m = ch.basic_get(Q, auto_ack=False)
            if m[0] is not None:
                return time.time() - t0, m
        finally:
            try:
                c.close()
            except Exception:
                pass
        time.sleep(0.3)
    return None, None


def scenario_a():
    """A：各 retry-type 值是否被接受"""
    print("\n【A】x-delayed-retry-type 各取值的声明结果")
    print("")
    print("| type | 声明结果 |")
    print("|------|----------|")
    for t in ['disabled', 'all', 'failed', 'returned', 'bogus_value']:
        try:
            declare_q(retry_type=t)
            print("| %s | ✅ 接受 |" % t)
        except Exception as e:
            print("| %s | ❌ 拒绝：%s |" % (t, str(e)[:60]))


def scenario_b():
    """B：线性退避是否成立（min=3000, max=12000）"""
    print("\n【B】延迟随返回次数线性增长（min=3000ms, max=12000ms）")
    declare_q(retry_type='all', rmin=3000, rmax=12000, delivery_limit=20)
    publish(b'B-retry-probe')
    time.sleep(1)

    print("")
    print("| 轮次 | 操作 | 等待再次可投递 | 理论延迟 |")
    print("|------|------|----------------|----------|")
    records = []
    for i in range(1, 5):
        # 取出并 nack(requeue=True) 触发延迟
        c = conn_of()
        ch = c.channel()
        m = ch.basic_get(Q, auto_ack=False)
        if m[0] is None:
            print("| %d | 无消息 | - | - |" % i)
            break
        method, props, body = m
        # 记录 headers 中的计数
        hdrs = props.headers if props and props.headers else {}
        ch.basic_nack(method.delivery_tag, requeue=True)
        c.close()

        t0 = time.time()
        t, _ = wait_ready(timeout=25)
        if t is None:
            print("| %d | nack(requeue=True) | 超时未返回 | %d ms |" % (
                i, min(3000 * i, 12000)))
            break
        theory = min(3000 * i, 12000) / 1000
        print("| %d | nack(requeue=True) | %.2f s | %.1f s |" % (i, t, theory))
        records.append((i, t, theory, hdrs))
        # 取出来准备下一轮（这条要被再 nack）
    return records


def scenario_c():
    """C：nack vs reject 是否触发延迟"""
    print("\n【C】nack 与 reject 对延迟/计数的影响")
    declare_q(retry_type='all', rmin=3000, rmax=12000, delivery_limit=20)
    publish(b'C-nack')
    time.sleep(1)
    c = conn_of()
    ch = c.channel()
    m = ch.basic_get(Q, auto_ack=False)
    if m[0]:
        method_c, _, _ = m
        ch.basic_nack(method_c.delivery_tag, requeue=True)
        print("  nack(requeue=True) 已执行，等待返回...")
    c.close()
    t, mt = wait_ready(timeout=20)
    if mt and mt[1]:
        props = mt[1]
        hdrs = props.headers or {}
        print("  返回耗时：%s" % ("%.2f s" % t if t else "超时"))
        print("  消息 headers：%s" % (hdrs if hdrs else "（无）"))
        print("  x-delay 相关：%s" % {k: v for k, v in hdrs.items()
                                      if 'delay' in k.lower() or 'count' in k.lower()})
        if mt[0]:
            c = conn_of()
            ch = c.channel()
            ch.basic_ack(mt[0].delivery_tag)
            c.close()
    else:
        print("  nack 后消息未返回（可能被丢弃或仍在延迟中）")


def main():
    print("=" * 74)
    print("课 10 实验 2：quorum 队列原生延迟重试（4.3 新增）")
    print("=" * 74)
    print("环境：RabbitMQ 4.3.5 / pika %s" % pika.__version__)

    scenario_a()
    r = scenario_b()
    scenario_c()

    # 清理
    c = conn_of()
    ch = c.channel()
    try:
        ch.queue_delete(queue=Q)
    except Exception:
        pass
    c.close()
    print("\n已清理")
    return 0


if __name__ == '__main__':
    sys.exit(main())
