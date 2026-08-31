#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8《交付语义与幂等》事实守护脚本
=====================================
用途：守护本课的核心硬事实，防止版本升级或环境变化后结论被推翻却无人察觉。
      每学完一课运行一次；若某项 FAIL，说明该结论已失效，必须复查讲义。

守护清单（共 7 条）：
  F1  at-most-once 崩溃丢失放大效应
      auto_ack=True 且 prefetch 无上限时，业务回调只执行 1 条就崩溃，
      队列剩余应为 0（即 100 条全丢），而非剩 99 条。
      意义：证明"丢的不是正在处理的 1 条，而是 broker 已推的全部"。

  F2  prefetch 对 auto_ack 无效（课 6 结论复核）
      加 prefetch_count=1 后，同样崩溃依然全丢。

  F3  手动 ack 零丢失 + redelivered 标记
      auto_ack=False + prefetch=1 崩溃 → 消息全部回到队列（零丢失），
      且重新消费时首条 redelivered=True。

  F4  生产侧重复无标记（★最危险的一条）
      连续发布两条同业务单号消息 → 两条 redelivered 均为 False，
      证明 broker 无法识别生产侧重复。

  F5  requeue 在队列有积压时会破坏顺序
      prefetch 放大 + 中间消息 nack(requeue=True) → 该消息被挤到队尾。

  F6  单消费者严格保序
      单消费者 + prefetch=1 → 完成顺序严格等于投递顺序。

  F7  单消费者 prefetch 吞吐：p=50 显著高于 p=1（≥3 倍）
      防止被污染的吞吐数据回流（l8-ordering.py 曾因多线程共享计数锁测低）。

运行：python l8-guard-facts.py
退出码：0 = 全部通过；1 = 至少一项失败
"""
import time
import sys
import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')

results = []


def record(fid, desc, ok, detail):
    results.append({'id': fid, 'desc': desc, 'ok': ok, 'detail': detail})
    flag = "PASS" if ok else "FAIL"
    print(f"  [{flag}] {fid} {desc}")
    print(f"         {detail}")


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


def setup(q):
    c = conn()
    ch = c.channel()
    ch.queue_declare(queue=q, durable=True)
    c.close()


def publish(q, n):
    c = conn()
    ch = c.channel()
    ch.confirm_delivery()
    for i in range(1, n + 1):
        ch.basic_publish(exchange='', routing_key=q, body=f'msg-{i:02d}'.encode(),
                         properties=pika.BasicProperties(delivery_mode=2))
    c.close()


print("=" * 74)
print("课 8 事实守护脚本 —— 验证 7 条硬事实")
print("=" * 74)

N = 100

# ---------------- F1 / F2：auto_ack 崩溃丢失放大 ----------------
for fid, prefetch in (('F1', None), ('F2', 1)):
    q = f'l8.guard.{fid.lower()}'
    reset(q)
    setup(q)
    publish(q, N)
    got = []

    def cb(ch, method, properties, body):
        got.append(body.decode())
        raise SystemExit(0)

    c = conn()
    ch = c.channel()
    if prefetch:
        ch.basic_qos(prefetch_count=prefetch)
    ch.basic_consume(queue=q, on_message_callback=cb, auto_ack=True)
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
    remain = depth(q)
    lost = N - remain
    ok = (remain == 0 and len(got) == 1)
    record(fid,
           f"auto_ack 崩溃丢失放大效应（prefetch={prefetch}）",
           ok,
           f"回调执行 {len(got)} 条后崩溃 → 队列剩 {remain} 条 / 丢失 {lost} 条"
           f"（期望：剩 0 / 丢 {N}，即丢失远多于已处理）")

# ---------------- F3：手动 ack 零丢失 + redelivered ----------------
q = 'l8.guard.f3'
reset(q)
setup(q)
publish(q, 10)
got3 = []


def cb3(ch, method, properties, body):
    got3.append(body.decode())
    raise SystemExit(0)


c = conn()
ch = c.channel()
ch.basic_qos(prefetch_count=1)
ch.basic_consume(queue=q, on_message_callback=cb3, auto_ack=False)
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
remain3 = depth(q)

# 重新消费，检查首条 redelivered
flags = []
seen = []


def cb3b(ch, method, properties, body):
    seen.append(body.decode())
    flags.append(method.redelivered)
    ch.basic_ack(delivery_tag=method.delivery_tag)


c = conn()
ch = c.channel()
ch.basic_qos(prefetch_count=1)
ch.basic_consume(queue=q, on_message_callback=cb3b, auto_ack=False)
deadline = time.time() + 6
while len(seen) < 2 and time.time() < deadline:
    c.process_data_events(time_limit=0.3)
c.close()

ok3 = (remain3 == 10 and flags and flags[0] is True)
record('F3', "手动 ack 零丢失 + 重投带 redelivered 标记", ok3,
       f"崩溃后队列剩 {remain3}/10 条（期望 10=零丢失）；重消费首条 redelivered={flags[0] if flags else 'N/A'}（期望 True）")

# ---------------- F4：生产侧重复无标记 ----------------
q = 'l8.guard.f4'
reset(q)
setup(q)
BIZ = 'GUARD-ORDER-001'
c = conn()
ch = c.channel()
ch.confirm_delivery()
for k in (1, 2):
    ch.basic_publish(exchange='', routing_key=q, body=f'pay:{BIZ}'.encode(),
                     properties=pika.BasicProperties(delivery_mode=2, message_id=f'{BIZ}#{k}'))
c.close()

seen4 = []
flags4 = []


def cb4(ch, method, properties, body):
    seen4.append(body.decode())
    flags4.append(method.redelivered)
    ch.basic_ack(delivery_tag=method.delivery_tag)


c = conn()
ch = c.channel()
ch.basic_consume(queue=q, on_message_callback=cb4, auto_ack=False)
deadline = time.time() + 6
while len(seen4) < 2 and time.time() < deadline:
    c.process_data_events(time_limit=0.3)
c.close()

ok4 = (len(seen4) == 2 and all(f is False for f in flags4))
record('F4', "★生产侧重复：broker 不打任何重投标记", ok4,
       f"发布 2 条同单号消息 → 收到 {len(seen4)} 条，redelivered 序列={flags4}（期望 [False, False]）")

# ---------------- F5：requeue 在积压时破坏顺序 ----------------
q = 'l8.guard.f5'
reset(q)
setup(q)
publish(q, 8)
order5 = []
attempts5 = {}
failed = {'done': False}


def cb5(ch, method, properties, body):
    name = body.decode()
    attempts5[name] = attempts5.get(name, 0) + 1
    if name == 'msg-03' and attempts5[name] == 1 and not failed['done']:
        failed['done'] = True
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
        return
    order5.append(name)
    ch.basic_ack(delivery_tag=method.delivery_tag)


c = conn()
ch = c.channel()
ch.basic_qos(prefetch_count=8)
ch.basic_consume(queue=q, on_message_callback=cb5, auto_ack=False)
deadline = time.time() + 12
while len(order5) < 8 and time.time() < deadline:
    c.process_data_events(time_limit=0.3)
c.close()

pos3 = order5.index('msg-03') if 'msg-03' in order5 else -1
ok5 = (pos3 > 2)
record('F5', "requeue 在客户端有积压时把消息挤到队尾（破坏顺序）", ok5,
       f"完成顺序 {' '.join(order5)}；msg-03 位置=第 {pos3 + 1} 位（期望 >3，即被挤后）")

# ---------------- F6：单消费者严格保序 ----------------
q = 'l8.guard.f6'
reset(q)
setup(q)
publish(q, 12)
order6 = []


def cb6(ch, method, properties, body):
    order6.append(body.decode())
    ch.basic_ack(delivery_tag=method.delivery_tag)


c = conn()
ch = c.channel()
ch.basic_qos(prefetch_count=1)
ch.basic_consume(queue=q, on_message_callback=cb6, auto_ack=False)
deadline = time.time() + 12
while len(order6) < 12 and time.time() < deadline:
    c.process_data_events(time_limit=0.3)
c.close()

expected = [f'msg-{i:02d}' for i in range(1, 13)]
ok6 = (order6 == expected)
record('F6', "单消费者 + prefetch=1 严格保序", ok6,
       f"顺序={' '.join(order6)}（期望严格递增）")

# ---------------- F7：单消费者 prefetch 吞吐曲线（课 8 P0 修正项） ----------------
# 背景：l8-ordering.py 因多线程共享计数锁，测出 p=1 仅 3152、p=50 仅 13339 条/秒（污染值）
#       l8-order-crosscheck.py 用独立计数 + barrier 重测得 3716 / 31721 条/秒（干净值）
# 守护目标：确认 p=50 相对 p=1 有显著（≥3 倍）提升，且 p=1 落在合理量级
M_TP = 600


def throughput_single(qname, prefetch):
    reset(qname)
    setup(qname)
    publish(qname, M_TP)
    c = conn()
    ch = c.channel()
    ch.basic_qos(prefetch_count=prefetch)
    cnt = [0]

    def cb(ch, method, properties, body):
        ch.basic_ack(delivery_tag=method.delivery_tag)
        cnt[0] += 1

    ch.basic_consume(queue=qname, on_message_callback=cb, auto_ack=False)
    t0 = time.time()
    deadline = t0 + 30
    while cnt[0] < M_TP and time.time() < deadline:
        c.process_data_events(time_limit=0.2)
    dt = time.time() - t0
    try:
        c.close()
    except Exception:
        pass
    return cnt[0] / dt if dt > 0 else 0


tp1 = throughput_single('l8.guard.f7a', 1)
tp50 = throughput_single('l8.guard.f7b', 50)
ratio = tp50 / tp1 if tp1 > 0 else 0
ok7 = (ratio >= 3.0)
record('F7', "单消费者 prefetch 吞吐：p=50 显著高于 p=1（≥3 倍）", ok7,
       f"p=1 → {tp1:.0f} 条/秒；p=50 → {tp50:.0f} 条/秒；倍数 {ratio:.1f}x"
       f"（期望 ≥3.0；若 p=1 低至 ~3150 且 p=50 仅 ~13300 则说明落回污染测量）")

# ---------------- 汇总 ----------------
print("\n" + "=" * 74)
passed = sum(1 for r in results if r['ok'])
total = len(results)
print(f"守护结果：{passed}/{total} 项通过")
print("=" * 74)
for r in results:
    flag = "PASS" if r['ok'] else "FAIL ★需复查"
    print(f"  [{flag:12s}] {r['id']}  {r['desc']}")

if passed < total:
    print(f"\n⚠️ 有 {total - passed} 项事实已失效，本课讲义相关结论必须复查！")
    sys.exit(1)
print("\n✅ 全部事实有效，讲义结论可信。")
sys.exit(0)
