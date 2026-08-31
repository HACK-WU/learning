#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8 知识点 1 深度验证：auto_ack 下崩溃的丢失放大效应
=======================================================
背景（重要发现）：
  小规模实验中，投递 5 条、业务回调只执行了 2 条就崩溃，队列剩余却是 0 条 → 丢了 5 条。
  即：丢失条数 >> 已处理条数。多出来的消息去哪了？

假设：
  auto_ack=True 且 prefetch 无上限时，broker 会把队列里的消息"一口气"推送给客户端，
  推送瞬间即视为已确认并删除。而 pika 客户端把这些帧缓存在接收缓冲区里，
  业务回调是逐条慢慢执行的。
  → 缓冲区里还没来得及回调的那些消息，进程一崩就全没了。

验证方法（放大法）：
  投递 N 条（N = 100），消费者只在第 1 条就崩溃，观察丢失条数。
  若丢失 ≈ N（而非 1），则证实"丢失放大效应"。

对照组：
  C 组：auto_ack=False + prefetch=1，同样第 1 条后崩溃 → 应只丢 0 条（消息回到队列）
"""
import time
import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')
N = 100


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


def publish(q, n):
    c = conn()
    ch = c.channel()
    ch.queue_declare(queue=q, durable=True)
    for i in range(1, n + 1):
        ch.basic_publish(exchange='', routing_key=q, body=f'm{i}'.encode(),
                         properties=pika.BasicProperties(delivery_mode=2))
    c.close()


print("=" * 74)
print(f"验证：auto_ack 崩溃的『丢失放大效应』（N={N}）")
print("=" * 74)

# ---------------- A 组：auto_ack=True，第 1 条就崩 ----------------
QA = 'l8.mag.autoack'
reset(QA)
publish(QA, N)
got_a = []


def on_a(ch, method, properties, body):
    got_a.append(body.decode())
    raise SystemExit(0)      # 第 1 条就崩


c = conn()
ch = c.channel()
ch.basic_consume(queue=QA, on_message_callback=on_a, auto_ack=True)
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

time.sleep(1.5)
remain_a = depth(QA)
lost_a = N - remain_a
print(f"\n  [A 组] auto_ack=True（无 prefetch）")
print(f"    投递 {N} 条，业务回调执行 {len(got_a)} 条后崩溃")
print(f"    队列剩余 = {remain_a} 条")
print(f"    >>> 丢失 {lost_a} 条  ← 若 ≈ {N} 则证实丢失放大效应")

# ---------------- B 组：auto_ack=True + prefetch=1 ----------------
QB = 'l8.mag.autoack_qos'
reset(QB)
publish(QB, N)
got_b = []


def on_b(ch, method, properties, body):
    got_b.append(body.decode())
    raise SystemExit(0)


c = conn()
ch = c.channel()
ch.basic_qos(prefetch_count=1)
ch.basic_consume(queue=QB, on_message_callback=on_b, auto_ack=True)
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

time.sleep(1.5)
remain_b = depth(QB)
lost_b = N - remain_b
print(f"\n  [B 组] auto_ack=True + prefetch_count=1")
print(f"    投递 {N} 条，业务回调执行 {len(got_b)} 条后崩溃")
print(f"    队列剩余 = {remain_b} 条")
print(f"    >>> 丢失 {lost_b} 条")

# ---------------- C 组：auto_ack=False + prefetch=1（正确姿势） ----------------
QC = 'l8.mag.manual'
reset(QC)
publish(QC, N)
got_c = []


def on_c(ch, method, properties, body):
    got_c.append(body.decode())
    raise SystemExit(0)      # 不 ack


c = conn()
ch = c.channel()
ch.basic_qos(prefetch_count=1)
ch.basic_consume(queue=QC, on_message_callback=on_c, auto_ack=False)
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

time.sleep(1.5)
remain_c = depth(QC)
lost_c = N - remain_c
print(f"\n  [C 组] auto_ack=False + prefetch_count=1（推荐姿势）")
print(f"    投递 {N} 条，业务回调执行 {len(got_c)} 条后崩溃（未 ack）")
print(f"    队列剩余 = {remain_c} 条")
print(f"    >>> 丢失 {lost_c} 条  ← 应为 0（消息全部回到队列）")

print("\n" + "=" * 74)
print("结论")
print("=" * 74)
print(f"  A 组 auto_ack=True           : 丢失 {lost_a}/{N} 条（回调仅执行 {len(got_a)} 条）")
print(f"  B 组 auto_ack + prefetch=1   : 丢失 {lost_b}/{N} 条（回调仅执行 {len(got_b)} 条）")
print(f"  C 组 手动 ack + prefetch=1   : 丢失 {lost_c}/{N} 条（回调仅执行 {len(got_c)} 条）")
print()
if lost_a > len(got_a):
    print(f"  ✅ 丢失放大效应成立：回调只跑了 {len(got_a)} 条，却丢了 {lost_a} 条。")
    print(f"     多出的 {lost_a - len(got_a)} 条是在『pika 接收缓冲区』里阵亡的 ——")
    print(f"     broker 早已把它们标记为已确认并删除，业务代码根本没看见。")
    print()
    print(f"  ⚠️ 这是 auto_ack 最危险的隐藏代价：")
    print(f"     崩溃时丢的不是『正在处理的 1 条』，而是『broker 已推、业务未处理』的全部。")
    print(f"     队列积压越多，一次崩溃损失越大。")
else:
    print(f"  ⚠️ 未观察到放大效应：丢失 {lost_a} 条 ≈ 已处理 {len(got_a)} 条")
print()
if lost_b == lost_a:
    print(f"  ✅ prefetch=1 救不了 auto_ack（丢失同为 {lost_a} 条）—— 课 6 结论再次验证：")
    print(f"     prefetch 约束的是『未确认数』，auto_ack 下投递即确认，无处可限。")
print()
if lost_c == 0:
    print(f"  ✅ 手动 ack 零丢失：{N} 条全部安全回到队列，可再次消费。")
    print(f"     代价：这些消息会被重新投递（重复），所以业务必须幂等 → 知识点 2")
