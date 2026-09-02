#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
确认：Lua 原子性没问题，之前是我的统计口径错了

关键认知：EVAL 返回 0 有歧义——
  - 「扣减成功，扣完剩 0」（最后一个抢到的人）
  - 「库存已空，扣减失败」
两者无法从返回值区分。这是接口设计缺陷，生产上必须改掉。

正确做法：让脚本返回结构化信息，例如返回剩余库存 + 明确的状态位，
或在脚本内用不同负数表示不同失败原因。
"""
import sys, threading
sys.path.insert(0, '.')
from redislib import conn_master

GID = 9003
INIT = 20
NTHREADS = 50

# 改进版脚本：用返回值明确区分结果，消除 0 的歧义
#   >=0          扣减成功，返回扣减后剩余
#   -1           库存 key 不存在
#   -2           库存不足，扣减失败
LUA_V2 = """
local stock = tonumber(redis.call('GET', KEYS[1]))
if stock == nil then return -1 end
if stock <= 0 then return -2 end
redis.call('DECRBY', KEYS[1], 1)
return stock - 1
"""

r = conn_master()
r.cmd('SET', 'inventory:stock:%d' % GID, INIT)

results = []
lock = threading.Lock()

def worker(uid):
    rr = conn_master()
    try:
        ret = rr.cmd('EVAL', LUA_V2, 1, 'inventory:stock:%d' % GID, 1)
        with lock:
            results.append(ret)
    finally:
        rr.close()

ts = [threading.Thread(target=worker, args=(i,)) for i in range(NTHREADS)]
for t in ts: t.start()
for t in ts: t.join()

left = int(r.cmd('GET', 'inventory:stock:%d' % GID))

succ = sum(1 for x in results if isinstance(x, int) and x >= 0)
fail = sum(1 for x in results if x == -2)
other = sum(1 for x in results if x == -1)

print('=' * 66)
print('  改进版脚本（返回值无歧义）')
print('=' * 66)
print('  初始库存 %d，并发 %d 线程' % (INIT, NTHREADS))
print('  成功(>=0) = %d' % succ)
print('  库存不足(-2) = %d' % fail)
print('  key 不存在(-1) = %d' % other)
print('  合计 = %d（应 = %d）' % (succ + fail + other, NTHREADS))
print('  最终剩余库存 = %d' % left)
print('  成功 + 剩余 = %d（应 = %d）' % (succ + left, INIT))
print()
ok = (succ + left == INIT) and left >= 0 and (succ + fail + other == NTHREADS)
print('  结论：%s' % ('✓ 账目完全对平，无超卖' if ok else '✗ 仍不平'))

# 对照：把 V1 的歧义演示出来
print()
print('=' * 66)
print('  对照：V1 脚本返回 0 的歧义')
print('=' * 66)
print('  V1 返回 0 时，调用方无法区分：')
print('    (a) 我扣减成功了，现在库存是 0  —— 应该给用户发券')
print('    (b) 你来晚了，库存早就空了      —— 应该提示已售罄')
print('  两者业务处理完全不同，返回值却一样 → 这是接口设计缺陷')
print('  V2 用 -2 明确表示失败，0 只表示"扣完剩 0"，歧义消除')
