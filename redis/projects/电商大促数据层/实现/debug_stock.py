#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
定位：库存统计错乱的根因

假设：多个线程共用同一个 Redis 连接（同一个 socket），
      RESP 协议是「请求-响应严格配对」的，多线程并发读写同一个 socket
      会导致响应错位——A 线程读到 B 线程的返回值。

验证方法：
  1) 多线程共用一个连接   → 预期账目错乱
  2) 每个线程独立连接     → 预期账目正确
"""
import sys, time, threading
sys.path.insert(0, '.')
from redislib import Redis, RedisError, conn_master

GID = 9001
INIT = 100

LUA_DEDUCT = """
local stock = tonumber(redis.call('GET', KEYS[1]))
if stock == nil then return -1 end
if stock <= 0 then return 0 end
redis.call('DECRBY', KEYS[1], 1)
return stock - 1
"""


def reset(r):
    r.cmd('SET', 'inventory:stock:%d' % GID, INIT)
    r.cmd('DEL', 'inventory:buyers:%d' % GID)


def run(shared_conn, nthreads=200, label=''):
    """shared_conn=True → 共用连接；False → 每线程独立连接"""
    r0 = conn_master()
    reset(r0)
    r0.close()

    results = []
    lock = threading.Lock()
    if shared_conn:
        shared = conn_master()   # 所有线程共用这一个

    def worker(uid):
        try:
            r = shared if shared_conn else conn_master()
            ret = r.cmd('EVAL', LUA_DEDUCT, 1,
                        'inventory:stock:%d' % GID, 1)
            with lock:
                results.append(ret)
            if not shared_conn:
                r.close()
        except Exception as e:
            with lock:
                results.append('ERR:%s' % str(e)[:60])

    ts = [threading.Thread(target=worker, args=(i,)) for i in range(nthreads)]
    t0 = time.time()
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    dt = time.time() - t0

    if shared_conn:
        shared.close()

    r1 = conn_master()
    left = r1.cmd('GET', 'inventory:stock:%d' % GID)
    r1.close()
    left = int(left) if left is not None else None

    # 统计
    def count(pred):
        return sum(1 for x in results if isinstance(x, int) and pred(x))
    ok = count(lambda x: x >= 0)
    empty = count(lambda x: x == 0)
    errs = sum(1 for x in results if isinstance(x, str))

    print('  %s' % label)
    print('    线程数 %d，耗时 %.3fs' % (nthreads, dt))
    print('    返回值分布：成功(>=0)=%d, 库存不足(=0)=%d, 异常=%d, 合计=%d'
          % (ok, empty, errs, len(results)))
    print('    最终剩余库存 = %s，初始 = %d' % (left, INIT))
    print('    成功数 + 剩余 = %d' % (ok + (left or 0)))
    verdict = '✓ 账目平，无超卖' if (ok + (left or 0) == INIT and (left or 0) >= 0) \
        else '✗ 账目错乱'
    print('    %s' % verdict)
    return verdict


if __name__ == '__main__':
    print('=' * 70)
    print('  实验：多线程共用连接的响应错位问题')
    print('=' * 70)

    print('\n--- 场景 A：所有线程共用同一个连接（错误写法） ---')
    run(shared_conn=True, nthreads=200, label='共用连接')

    print('\n--- 场景 B：每个线程独立连接（正确写法） ---')
    run(shared_conn=False, nthreads=200, label='独立连接')

    print('\n--- 场景 C：再次共用连接（确认可复现） ---')
    run(shared_conn=True, nthreads=200, label='共用连接（复现）')
