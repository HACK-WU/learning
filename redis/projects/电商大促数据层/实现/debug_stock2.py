#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
精确定位：直接看 EVAL 的原始返回值分布，不套任何统计逻辑
"""
import sys, threading
sys.path.insert(0, '.')
from redislib import conn_master
from collections import Counter

GID = 9002
INIT = 20          # 小库存，让成功/失败都出现
NTHREADS = 50

LUA = """
local stock = tonumber(redis.call('GET', KEYS[1]))
if stock == nil then return -1 end
if stock <= 0 then return 0 end
redis.call('DECRBY', KEYS[1], 1)
return stock - 1
"""

r = conn_master()
r.cmd('SET', 'inventory:stock:%d' % GID, INIT)
r.cmd('DEL', 'inventory:buyers:%d' % GID)

print('初始库存 = %d，并发线程 = %d' % (INIT, NTHREADS))

results = []
lock = threading.Lock()

def worker(uid):
    rr = conn_master()          # 每线程独立连接
    try:
        ret = rr.cmd('EVAL', LUA, 1, 'inventory:stock:%d' % GID, 1)
        with lock:
            results.append(ret)
    finally:
        rr.close()

ts = [threading.Thread(target=worker, args=(i,)) for i in range(NTHREADS)]
for t in ts: t.start()
for t in ts: t.join()

print('\n原始返回值（前 30 个）：')
print('  ', results[:30])
print('\n返回值分布 Counter：')
cnt = Counter(results)
for k, v in sorted(cnt.items(), key=lambda x: (isinstance(x[0], str), x[0] if not isinstance(x[0], str) else 0)):
    print('    %-6s : %d 次' % (k, v))

left = int(r.cmd('GET', 'inventory:stock:%d' % GID))
print('\n最终剩余库存 = %d' % left)

# 正确统计：成功 = 返回值 >= 1（扣减后剩余），0 = 库存不足
succ = sum(1 for x in results if isinstance(x, int) and x >= 0 and x != 0)
succ2 = sum(1 for x in results if isinstance(x, int) and x >= 1)
fail = sum(1 for x in results if x == 0)
print('\n按「返回值 >= 1」统计成功数 = %d' % succ2)
print('按「返回值 == 0」统计失败数 = %d' % fail)
print('成功 + 失败 = %d（应等于线程数 %d）' % (succ + fail, NTHREADS))
print('成功 + 剩余 = %d（应等于初始 %d）' % (succ2 + left, INIT))
print('\n结论：%s' % ('✓ 无超卖，账目平' if succ2 + left == INIT else '✗ 账目不平'))
print('      %s' % ('✓ 返回值总数对得上' if len(results) == NTHREADS else '✗ 返回值丢失'))
