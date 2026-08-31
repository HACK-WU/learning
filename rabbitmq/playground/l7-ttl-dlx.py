#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 7 知识点 3：TTL 与死信队列

覆盖内容：
  1. 两种 TTL
       - 队列级 x-message-ttl（整个队列统一过期时间）
       - 消息级 expiration（每条消息各自过期）
       - 二者同时存在时：**取较小值**
  2. 三种死信来源（dead-lettering 触发条件）
       - rejected：消费者 basic.reject / basic.nack 且 requeue=False
       - expired：消息 TTL 到期（注意：只有队首消息过期才会真正被丢弃/死信）
       - maxlen：队列超过 x-max-length 或 x-max-length-bytes
  3. 死信路由
       - x-dead-letter-exchange（DLX）+ x-dead-letter-routing-key（DLK）
       - 未指定 DLK 时，沿用原 routing key
       - 死信消息会带上 x-death 头（课 6 已证明 requeue=True 不写 x-death！）
  4. 经典用法：延迟重试链路（TTL + DLX）
"""
import os
import time

import pika

HOST = os.environ.get("RMQ_HOST", "127.0.0.1")
PORT = int(os.environ.get("RMQ_PORT", "5672"))
USER = os.environ.get("RMQ_USER", "learn")
PASS = os.environ.get("RMQ_PASS", "learn123")

PARAMS = pika.ConnectionParameters(
    host=HOST, port=PORT, credentials=pika.PlainCredentials(USER, PASS)
)


def conn():
    return pika.BlockingConnection(PARAMS)


def purge(q):
    c = conn()
    ch = c.channel()
    try:
        ch.queue_purge(q)
    except Exception:  # noqa: BLE001
        pass
    c.close()


def depth(q):
    """用 passive 声明读队列深度（比 rabbitmqctl 更及时）"""
    c = conn()
    ch = c.channel()
    try:
        r = ch.queue_declare(queue=q, durable=True, passive=True)
        n = r.method.message_count
    except Exception:  # noqa: BLE001
        n = -1
    c.close()
    return n


def sep(title):
    print("\n" + "=" * 72)
    print(f"  {title}")
    print("=" * 72)


# ---------------------------------------------------------------- 1. 两种 TTL
def test_two_ttl():
    sep("1. 两种 TTL：队列级 x-message-ttl vs 消息级 expiration")

    c = conn()
    ch = c.channel()
    ch.exchange_declare(exchange="l7.ttl.ex", exchange_type="direct", durable=True)

    # 队列级 TTL = 3 秒
    ch.queue_declare(queue="l7.ttl.q", durable=True,
                     arguments={"x-message-ttl": 3000})
    ch.queue_bind(exchange="l7.ttl.ex", queue="l7.ttl.q", routing_key="k")
    ch.close(); c.close()

    # 消息级 TTL = 10 秒（比队列级大）
    c = conn(); ch = c.channel()
    ch.basic_publish(exchange="l7.ttl.ex", routing_key="k",
                     body=b"msg-ttl-10s",
                     properties=pika.BasicProperties(
                         delivery_mode=2, expiration="10000"))
    # 消息级 TTL = 1 秒（比队列级小）
    ch.basic_publish(exchange="l7.ttl.ex", routing_key="k",
                     body=b"msg-ttl-1s",
                     properties=pika.BasicProperties(
                         delivery_mode=2, expiration="1000"))
    ch.close(); c.close()

    print("\n  队列 TTL=3s；发两条：A(expiration=10s) 与 B(expiration=1s)")
    print(f"  t=0.5s  队列深度 = {depth('l7.ttl.q')}  （期望 2）")
    time.sleep(2.0)
    print(f"  t=2.5s  队列深度 = {depth('l7.ttl.q')}  （B 的 1s TTL 已到，期望 1）")
    time.sleep(2.0)
    print(f"  t=4.5s  队列深度 = {depth('l7.ttl.q')}  （A 取队列级 3s ← 二者取小，期望 0）")


# ---------------------------------------------------------- 2. 三种死信来源
def test_dead_letter_sources():
    sep("2. 三种死信来源：rejected / expired / maxlen")

    c = conn()
    ch = c.channel()
    # 死信交换机与死信队列
    ch.exchange_declare(exchange="l7.dlx", exchange_type="fanout", durable=True)
    ch.queue_declare(queue="l7.dead.q", durable=True)
    ch.queue_bind(exchange="l7.dlx", queue="l7.dead.q")
    ch.close(); c.close()

    # --- 来源 A：rejected（nack + requeue=False）---
    c = conn(); ch = c.channel()
    ch.queue_declare(queue="l7.src.reject", durable=True,
                     arguments={"x-dead-letter-exchange": "l7.dlx"})
    ch.basic_publish(exchange="", routing_key="l7.src.reject",
                     body=b"to-be-rejected",
                     properties=pika.BasicProperties(delivery_mode=2))
    ch.close(); c.close()

    c = conn(); ch = c.channel()
    method, props, body = next(ch.consume(queue="l7.src.reject",
                                          auto_ack=False, inactivity_timeout=3))
    if method:
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)
        print(f"\n  A. rejected：nack(requeue=False) 消息「{body.decode()}」")
    ch.close(); c.close()
    time.sleep(0.5)
    print(f"     → 源队列剩余 {depth('l7.src.reject')}（期望 0），"
          f"死信队列 {depth('l7.dead.q')}（期望 1）")

    # --- 来源 B：expired（TTL 到期）---
    c = conn(); ch = c.channel()
    ch.queue_declare(queue="l7.src.expire", durable=True,
                     arguments={"x-message-ttl": 1500,
                                "x-dead-letter-exchange": "l7.dlx"})
    ch.basic_publish(exchange="", routing_key="l7.src.expire",
                     body=b"to-be-expired",
                     properties=pika.BasicProperties(delivery_mode=2))
    ch.close(); c.close()
    print(f"\n  B. expired：消息 TTL=1.5s，当前死信队列 {depth('l7.dead.q')}")
    time.sleep(3.0)
    print(f"     3 秒后 → 源队列 {depth('l7.src.expire')}（期望 0），"
          f"死信队列 {depth('l7.dead.q')}（期望 2）")

    # --- 来源 C：maxlen（队列超长）---
    c = conn(); ch = c.channel()
    ch.queue_declare(queue="l7.src.maxlen", durable=True,
                     arguments={"x-max-length": 2,
                                "x-dead-letter-exchange": "l7.dlx"})
    for i in range(1, 5):
        ch.basic_publish(exchange="", routing_key="l7.src.maxlen",
                         body=f"m{i}".encode(),
                         properties=pika.BasicProperties(delivery_mode=2))
    ch.close(); c.close()
    time.sleep(0.5)
    print(f"\n  C. maxlen：x-max-length=2，发 4 条")
    print(f"     → 源队列保留 {depth('l7.src.maxlen')}（期望 2，最新 2 条），"
          f"死信队列 {depth('l7.dead.q')}（期望 4：前 2 条被挤入死信）")


# ------------------------------------------------------- 3. x-death 头内容
def test_xdeath():
    sep("3. 死信消息的 x-death 头（课 6 已证明 requeue=True 不写 x-death）")

    c = conn()
    ch = c.channel()
    method, props, body = next(ch.consume(queue="l7.dead.q",
                                          auto_ack=False, inactivity_timeout=3))
    if not method:
        print("  未取到死信消息")
        ch.close(); c.close()
        return

    print(f"\n  取到死信消息：body={body.decode()}")
    print(f"  x-death = {props.headers.get('x-death') if props.headers else None}")
    if props.headers and "x-death" in props.headers:
        for entry in props.headers["x-death"]:
            print(f"    queue={entry.get('queue')}  reason={entry.get('reason')}  "
                  f"count={entry.get('count')}  "
                  f"routing-keys={entry.get('routing-keys')}")
    ch.basic_ack(delivery_tag=method.delivery_tag)
    ch.close(); c.close()


# ------------------------------------------ 4. 经典用法：延迟重试链路
def test_delay_retry():
    sep("4. 经典用法：TTL + DLX 实现「延迟重试」")

    print("""
  链路设计：
    业务队列 l7.work  ──(失败 nack, requeue=False)──>  l7.dlx2 (DLX)
                                                          │
                                                          v
                                                    l7.retry.wait
                                                (x-message-ttl=3000,
                                                 x-dead-letter-exchange="" )
                                                          │ 3 秒后过期
                                                          v
                                                    回到 l7.work（重投）
    """)

    c = conn()
    ch = c.channel()
    # 死信交换机（direct，便于用不同 routing key 区分）
    ch.exchange_declare(exchange="l7.dlx2", exchange_type="direct", durable=True)

    # 业务队列：失败后死信到 l7.dlx2，routing key = retry
    ch.queue_declare(queue="l7.work", durable=True,
                     arguments={"x-dead-letter-exchange": "l7.dlx2",
                                "x-dead-letter-routing-key": "retry"})

    # 等待队列：TTL 3 秒，过期后死信回默认交换机 → 直接回到 l7.work
    ch.queue_declare(queue="l7.retry.wait", durable=True,
                     arguments={"x-message-ttl": 3000,
                                "x-dead-letter-exchange": "",
                                "x-dead-letter-routing-key": "l7.work"})
    ch.queue_bind(exchange="l7.dlx2", queue="l7.retry.wait", routing_key="retry")
    ch.close(); c.close()

    purge("l7.work")
    purge("l7.retry.wait")

    c = conn(); ch = c.channel()
    ch.basic_publish(exchange="", routing_key="l7.work", body=b"order-1001",
                     properties=pika.BasicProperties(delivery_mode=2))
    ch.close(); c.close()
    print(f"  t=0.0s  发布 order-1001 → l7.work，深度={depth('l7.work')}")

    # 第一次消费：模拟失败，nack requeue=False → 进入等待队列
    c = conn(); ch = c.channel()
    m, p, b = next(ch.consume(queue="l7.work", auto_ack=False, inactivity_timeout=3))
    if m:
        ch.basic_nack(delivery_tag=m.delivery_tag, requeue=False)
        print(f"  t=0.3s  消费失败，nack(requeue=False) → 消息进入 l7.retry.wait")
    ch.close(); c.close()
    time.sleep(0.5)
    print(f"  t=0.8s  l7.work={depth('l7.work')}（期望 0）  "
          f"l7.retry.wait={depth('l7.retry.wait')}（期望 1，等待 3 秒）")

    time.sleep(3.5)
    print(f"  t=4.3s  l7.work={depth('l7.work')}（期望 1 ← 3 秒 TTL 到期后重新投递）  "
          f"l7.retry.wait={depth('l7.retry.wait')}（期望 0）")

    # 第二次消费：成功
    c = conn(); ch = c.channel()
    m, p, b = next(ch.consume(queue="l7.work", auto_ack=False, inactivity_timeout=3))
    if m:
        print(f"  t=4.6s  再次消费：body={b.decode()}  "
              f"x-death={p.headers.get('x-death') if p.headers else None}")
        ch.basic_ack(delivery_tag=m.delivery_tag)
        print("          ack 成功，重试链路闭环")
    ch.close(); c.close()


if __name__ == "__main__":
    test_two_ttl()
    test_dead_letter_sources()
    test_xdeath()
    test_delay_retry()
