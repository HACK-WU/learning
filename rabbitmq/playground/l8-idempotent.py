#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8 知识点 2：重复来源与幂等设计
==================================
目标：实测证明"重复"不是理论风险，而是必然发生；并验证幂等方案能挡住它。

待验证的重复来源（RabbitMQ 语义层面）：
  S1 消费者处理成功但 ack 前崩溃    → 消息重投（已由知识点 1 B 组证实）
  S2 消费者处理成功但 ack 丢失/超时 → 消息重投
  S3 队列配置了 nack/requeue=True   → 显式要求重投
  S4 发布者超时重发（未收到 confirm 就重发）→ 同内容消息被发布两次（最隐蔽！）

核心区分（教学上极易混淆，必须讲清）：
  ■ 消费侧重复（S1/S2/S3）：broker 重投同一条消息 → 带 redelivered=True
  ■ 生产侧重复（S4）：broker 收到的是两条"不同"的消息
                      → redelivered=False（broker 眼里是全新的两条！）
  ⚠️ 后者最危险：它没有任何重投标记，消费者无法察觉，只能靠业务幂等键挡住。

幂等方案实测：
  - 用 message_id（或业务单号）作为幂等键 + 去重表（set 模拟）
  - 对比：不做幂等 → 业务重复执行 N 次；做了幂等 → 只执行 1 次

实测环境：RabbitMQ 4.3.5 / pika 1.4.4
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


def reset(*qs):
    c = conn()
    ch = c.channel()
    for q in qs:
        try:
            ch.queue_delete(queue=q)
        except Exception:
            pass
    c.close()


def setup(*qs):
    c = conn()
    ch = c.channel()
    for q in qs:
        ch.queue_declare(queue=q, durable=True)
    c.close()


print("=" * 74)
print("知识点 2：重复来源与幂等设计 —— 实测")
print("=" * 74)

# =====================================================================
# S3：nack(requeue=True) 产生重复 —— 验证 redelivered 标记
# =====================================================================
print("\n" + "-" * 74)
print("【S3】nack(requeue=True) → 显式重投")
print("-" * 74)

Q_S3 = 'l8.dup.requeue'
reset(Q_S3)
setup(Q_S3)

c = conn()
ch = c.channel()
ch.basic_publish(exchange='', routing_key=Q_S3, body=b'pay-1001',
                 properties=pika.BasicProperties(delivery_mode=2))
c.close()

attempts = []


def on_s3(ch, method, properties, body):
    attempts.append({'msg': body.decode(), 'redelivered': method.redelivered,
                     'tag': method.delivery_tag})
    n = len(attempts)
    print(f"    第 {n} 次收到 {body.decode()}，redelivered={method.redelivered}")
    if n < 3:
        print(f"      → nack(requeue=True)：要求 broker 重新投递")
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
    else:
        print(f"      → ack：处理完成")
        ch.basic_ack(delivery_tag=method.delivery_tag)


c = conn()
ch = c.channel()
ch.basic_consume(queue=Q_S3, on_message_callback=on_s3, auto_ack=False)
deadline = time.time() + 8
while len(attempts) < 3 and time.time() < deadline:
    c.process_data_events(time_limit=0.5)
time.sleep(0.5)
c.close()

flags_s3 = [a['redelivered'] for a in attempts]
print(f"\n    共被处理 {len(attempts)} 次，redelivered 序列 = {flags_s3}")
print(f"    >>> 同一条消息被处理了 {len(attempts)} 次 = 重复 {len(attempts) - 1} 次")
print(f"    >>> 首次投递标记 False、后续 True：{'成立' if flags_s3[0] is False and all(flags_s3[1:]) else '不成立'}")

# =====================================================================
# S4：发布者重发 → 生产侧重复（最隐蔽！redelivered=False）
# =====================================================================
print("\n" + "-" * 74)
print("【S4】发布者超时重发 → 生产侧重复（★最隐蔽）")
print("-" * 74)

Q_S4 = 'l8.dup.republish'
reset(Q_S4)
setup(Q_S4)

# 模拟：发布者以为第一次丢了（没收到 confirm / 超时），于是重发同样的内容
# 两条消息用同一个 message_id（业务单号），但 broker 视为两条独立消息
BIZ_ID = 'ORDER-2026-0801-9001'

for attempt in (1, 2):
    c = conn()
    ch = c.channel()
    ch.confirm_delivery()   # pika 方法名是 confirm_delivery（不是 confirm_select）
    ch.basic_publish(exchange='', routing_key=Q_S4,
                     body=f'pay:{BIZ_ID}'.encode(),
                     properties=pika.BasicProperties(
                         delivery_mode=2,
                         message_id=f'{BIZ_ID}#try{attempt}'))  # 注意 message_id 不同！
    c.close()
    print(f"    第 {attempt} 次发布：单号 {BIZ_ID}（发布者以为第 1 次失败了）")

print(f"\n    队列深度 = {depth(Q_S4)} 条")
print(f"    >>> broker 眼里这是 2 条独立消息（不是 1 条重投）")

# 消费，重点观察 redelivered 标记
seen_s4 = []


def on_s4(ch, method, properties, body):
    seen_s4.append({'body': body.decode(),
                    'redelivered': method.redelivered,
                    'message_id': properties.message_id,
                    'tag': method.delivery_tag})
    ch.basic_ack(delivery_tag=method.delivery_tag)


c = conn()
ch = c.channel()
ch.basic_consume(queue=Q_S4, on_message_callback=on_s4, auto_ack=False)
deadline = time.time() + 5
while len(seen_s4) < 2 and time.time() < deadline:
    c.process_data_events(time_limit=0.5)
c.close()

print(f"\n    消费到 {len(seen_s4)} 条：")
for s in seen_s4:
    print(f"      body={s['body']:28s} message_id={s['message_id']:28s} redelivered={s['redelivered']}")

all_false = all(s['redelivered'] is False for s in seen_s4)
print(f"\n    >>> 两条的 redelivered 都是 False：{all_false}")
if all_false and len(seen_s4) == 2:
    print(f"    ★ 这就是生产侧重复最危险的地方：")
    print(f"      broker 完全不知道这是重复，不会打任何标记。")
    print(f"      消费者看到的两条消息『看起来』都是全新的。")
    print(f"      唯一能识别它们的，是消息体里的业务单号 {BIZ_ID}。")

# =====================================================================
# 幂等方案：幂等键 + 去重表
# =====================================================================
print("\n" + "-" * 74)
print("【幂等方案】幂等键 + 去重表 —— 挡住重复")
print("-" * 74)

Q_IDEM = 'l8.dup.idem'
reset(Q_IDEM)
setup(Q_IDEM)

BIZ = 'ORDER-2026-0801-7777'

# 故意发布 3 条内容相同（同一业务单号）的消息，模拟各种重复来源叠加
c = conn()
ch = c.channel()
ch.confirm_delivery()
for k in range(3):
    ch.basic_publish(exchange='', routing_key=Q_IDEM,
                     body=f'pay:{BIZ}'.encode(),
                     properties=pika.BasicProperties(
                         delivery_mode=2,
                         message_id=BIZ,        # ★ 幂等键 = 业务单号（三次都一样）
                         timestamp=int(time.time())))
c.close()
print(f"    发布 3 条内容相同的消息（同一单号 {BIZ}），队列深度 = {depth(Q_IDEM)}")

# ---- 消费者 A：不做幂等 ----
biz_exec_a = []
exec_log_a = []


def on_no_idem(ch, method, properties, body):
    biz = body.decode()
    biz_exec_a.append(biz)                      # 模拟"扣款"业务动作
    exec_log_a.append(f"执行扣款 {biz}")
    ch.basic_ack(delivery_tag=method.delivery_tag)


# ---- 消费者 B：做幂等（去重表） ----
dedup_table = set()      # 生产环境换成 Redis SETNX / DB 唯一索引
biz_exec_b = []
exec_log_b = []


def on_idem(ch, method, properties, body):
    key = properties.message_id or body.decode()
    if key in dedup_table:
        exec_log_b.append(f"跳过 {key}（已处理过，命中去重表）")
        ch.basic_ack(delivery_tag=method.delivery_tag)
        return
    # ★ 关键：先登记去重表，再执行业务；或"业务+登记"放在同一个事务里
    dedup_table.add(key)
    biz_exec_b.append(body.decode())
    exec_log_b.append(f"执行扣款 {body.decode()}")
    ch.basic_ack(delivery_tag=method.delivery_tag)


# 先跑"不做幂等"
c = conn()
ch = c.channel()
ch.basic_consume(queue=Q_IDEM, on_message_callback=on_no_idem, auto_ack=False)
deadline = time.time() + 5
while len(biz_exec_a) < 3 and time.time() < deadline:
    c.process_data_events(time_limit=0.5)
c.close()

print(f"\n  [不幂等] 业务实际执行 {len(biz_exec_a)} 次：")
for log in exec_log_a:
    print(f"      {log}")
print(f"    >>> 用户被扣款 {len(biz_exec_a)} 次 = 重复扣款 {len(biz_exec_a) - 1} 次 ✗")

# 再跑"做幂等"（重新灌同样的数据）
reset(Q_IDEM)
setup(Q_IDEM)
c = conn()
ch = c.channel()
ch.confirm_delivery()
for k in range(3):
    ch.basic_publish(exchange='', routing_key=Q_IDEM,
                     body=f'pay:{BIZ}'.encode(),
                     properties=pika.BasicProperties(
                         delivery_mode=2, message_id=BIZ,
                         timestamp=int(time.time())))
c.close()

c = conn()
ch = c.channel()
ch.basic_consume(queue=Q_IDEM, on_message_callback=on_idem, auto_ack=False)
deadline = time.time() + 5
while len(biz_exec_b) < 1 and time.time() < deadline:
    c.process_data_events(time_limit=0.5)
deadline = time.time() + 3
while time.time() < deadline:
    c.process_data_events(time_limit=0.5)
c.close()

print(f"\n  [做幂等] 收到 3 条，业务实际执行 {len(biz_exec_b)} 次：")
for log in exec_log_b:
    print(f"      {log}")
print(f"    >>> 用户被扣款 {len(biz_exec_b)} 次 ✓（去重表挡住了 {3 - len(biz_exec_b)} 次重复）")

print("\n" + "=" * 74)
print("知识点 2 实测小结")
print("=" * 74)
print(f"  S1/S2 消费侧重复：redelivered=True，broker 主动标记，消费者可感知")
print(f"  S3   requeue    ：实测重复 {len(attempts) - 1} 次，标记序列 {flags_s3}")
print(f"  S4   生产侧重发：两条消息 redelivered 均为 False，broker 无从感知 ★最危险")
print(f"  幂等效果对比   ：不幂等扣款 {len(biz_exec_a)} 次 → 幂等后扣款 {len(biz_exec_b)} 次")
print()
print("  核心结论：")
print("   1. RabbitMQ 保证『至少一次』，重复是必然不是意外")
print("   2. 消费侧重复有 redelivered 标记；生产侧重复没有任何标记")
print("   3. 唯一通用解法：业务侧幂等键 + 去重表（Redis SETNX / DB 唯一索引）")
