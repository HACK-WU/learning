#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""课5 知识点1 实测（v2）：每个实验独立连接，避免 541 关连接污染后续"""
import pika

CR = pika.PlainCredentials('learn', 'learn123')
CP = pika.ConnectionParameters(host='localhost', port=5672, credentials=CR)

def new_ch():
    c = pika.BlockingConnection(CP)
    return c, c.channel()

def show(t):
    print(f"\n===== {t} =====")

# ---------- 实验 1：transient 非独占 → 541 且关闭整个连接 ----------
show("实验1：transient 非独占 classic（4.3 拒绝）")
c1, ch1 = new_ch()
try:
    ch1.queue_declare(queue='l5_trans_q', durable=False, exclusive=False)
    print(">>> 成功（与预期不符）")
except Exception as e:
    print(f">>> 拒绝: {type(e).__name__} code={getattr(e,'reply_code',None)}")
    print(f">>> 首行: {str(getattr(e,'reply_text',e)).splitlines()[0]}")
# 验证连接是否还活着
print(f">>> 该连接是否已关闭? {not (c1.is_open)}")
try:
    ch1.queue_declare(queue='l5_after_trans', durable=True)
    print(">>> 同连接后续操作：仍可用")
except Exception as e:
    print(f">>> 同连接后续操作失败（说明连接被 broker 关了）: {type(e).__name__}")
try:
    c1.close()
except Exception:
    pass

# ---------- 实验 2：exclusive 队列被其他连接访问 ----------
show("实验2：exclusive 队列的独占语义")
cA, chA = new_ch()
r = chA.queue_declare(queue='l5_excl_q2', durable=True, exclusive=True)
print(f"A 连接创建 exclusive 队列: {r.method.queue}")
print(f">>> A 连接存活中")

cB, chB = new_ch()
try:
    chB.queue_declare(queue='l5_excl_q2', durable=True, exclusive=True)
    print(">>> B 连接也能声明（与预期不符）")
except Exception as e:
    print(f">>> B 连接被拒绝: {type(e).__name__} code={getattr(e,'reply_code',None)}")
    print(f">>> 首行: {str(getattr(e,'reply_text',e)).splitlines()[0]}")
try:
    cB.close()
except Exception:
    pass

# ---------- 实验 3：A 连接断开后 exclusive 队列是否被删除 ----------
show("实验3：A 连接断开后，exclusive 队列是否自动删除")
try:
    cA.close()
    print("A 连接已关闭")
except Exception as e:
    print(f"关闭异常: {e}")

cC, chC = new_ch()
try:
    r2 = chC.queue_declare(queue='l5_excl_q2', durable=True, exclusive=True, passive=False)
    print(f">>> A 断开后，C 连接能重新声明同名 exclusive 队列 → 说明原队列已随连接删除")
except Exception as e:
    print(f">>> C 连接声明失败: {type(e).__name__} {getattr(e,'reply_text',e)}")
cC.close()

# ---------- 实验 4：exclusive 队列是"连接级"还是"信道级"独占 ----------
show("实验4：同一连接的另一个信道能否访问 exclusive 队列（连接级 or 信道级）")
cD, chD = new_ch()
chD.queue_declare(queue='l5_excl_q3', durable=True, exclusive=True)
print("D 连接 chD 创建了 l5_excl_q3")
try:
    chD2 = cD.channel()
    chD2.queue_declare(queue='l5_excl_q3', durable=True, exclusive=True, passive=True)
    print(">>> 同连接另一信道可以 passive 声明 → exclusive 是【连接级】独占")
except Exception as e:
    print(f">>> 同连接另一信道被拒: {type(e).__name__} {getattr(e,'reply_text',e)}")
try:
    cD.close()
except Exception:
    pass

print("\n===== 全部完成 =====")
