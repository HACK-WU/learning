#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8 知识点 1（击穿部分）实测：热点 key 过期的瞬间会发生什么。

四组实验：
  A. 无防护基线        —— N 个线程在 key 过期瞬间同时 miss，全部打到 DB
  B. 互斥锁/SET NX     —— 只有拿到锁的线程重建缓存，其余等待后重读
  C. 逻辑过期          —— 不设 TTL，永不过期；value 内带 expire 时间戳，异步刷新
  D. 永不过期 + 异步更新 —— 物理不过期，由后台任务刷新

度量指标：DB 查询次数、DB 瞬时最大并发、请求总耗时。
"""
import os
import sys
import time
import random
import threading
import importlib.util

_LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    'prep-lesson-08-lib.py')
_spec = importlib.util.spec_from_file_location('prep_lesson_08_lib', _LIB)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
Redis, FakeDB = _mod.Redis, _mod.FakeDB

PORT = 7101
HOT_KEY = 'product:hot:1001'
CONC = 200                 # 并发线程数
DB_LATENCY = 0.05          # DB 重建耗时 50ms（慢查询）
LOCK_TTL = 10              # 分布式锁 TTL（秒）
LOGIC_TTL = 5              # 逻辑过期时间（秒）


def banner(t):
    print('\n' + '=' * 64)
    print(t)
    print('=' * 64)


def conn():
    return Redis(port=PORT)


def run_concurrent(fn, n=CONC):
    """启动 n 个线程并发执行 fn(tid)，返回总耗时。"""
    barrier = threading.Barrier(n)
    errors = []
    lock = threading.Lock()

    def wrap(tid):
        try:
            barrier.wait()          # 尽量同时开跑
        except Exception:
            pass
        try:
            fn(tid)
        except Exception as e:
            with lock:
                errors.append('%s: %s' % (type(e).__name__, e))

    ts = [threading.Thread(target=wrap, args=(i,)) for i in range(n)]
    t0 = time.time()
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    return time.time() - t0, errors


# =========================================================
# A. 无防护基线
# =========================================================
def test_baseline():
    banner('A. 无防护基线 —— 热点 key 过期瞬间，%d 个请求同时 miss' % CONC)
    r = conn()
    r.flushdb()
    db = FakeDB(data={HOT_KEY: 'hot-value-v1'}, latency=DB_LATENCY)
    db.reset_stats()

    # 预热缓存，TTL 1 秒
    r.set(HOT_KEY, db.data[HOT_KEY], ex=1)
    print('预热: SET %s hot-value-v1 EX 1' % HOT_KEY)
    print('等待 1.2s 让 key 自然过期...')
    time.sleep(1.2)
    print('过期后缓存中是否还有: %r' % r.get(HOT_KEY))

    def worker(tid):
        rr = conn()
        try:
            v = rr.get(HOT_KEY)
            if v is None:
                val = db.get(HOT_KEY)       # 全部线程都去查 DB
                rr.set(HOT_KEY, val, ex=300)
        finally:
            rr.close()

    el, errs = run_concurrent(worker)
    print('并发请求数      : %d' % CONC)
    print('DB 查询次数     : %d  ← 每个 miss 的请求都查了一次' % db.queries)
    print('DB 瞬时最大并发 : %d  ← 同时压在 DB 上的连接数' % db.max_concurrent)
    print('总耗时          : %.3f s' % el)
    print('错误            : %d' % len(errs))
    if errs:
        print('  ', errs[:3])
    print('最终缓存值      : %r' % r.get(HOT_KEY))
    r.close()
    return db.queries, db.max_concurrent


# =========================================================
# B. 互斥锁（SET NX）
# =========================================================
def test_mutex():
    banner('B. 互斥锁重建 —— 只有拿到锁的线程查 DB，其余等待后重读缓存')
    r = conn()
    r.flushdb()
    db = FakeDB(data={HOT_KEY: 'hot-value-v1'}, latency=DB_LATENCY)
    db.reset_stats()

    r.set(HOT_KEY, db.data[HOT_KEY], ex=1)
    time.sleep(1.2)
    print('key 已过期，开始 %d 并发' % CONC)

    stats = {'lock_acquired': 0, 'waited': 0, 'db_direct': 0}
    slock = threading.Lock()

    def worker(tid):
        rr = conn()
        try:
            v = rr.get(HOT_KEY)
            if v is not None:
                return
            # 尝试获取重建锁
            got = rr.set('lock:' + HOT_KEY, '1', ex=LOCK_TTL, nx=True)
            if got:
                with slock:
                    stats['lock_acquired'] += 1
                try:
                    val = db.get(HOT_KEY)            # 只有 1 次 DB 查询
                    rr.set(HOT_KEY, val, ex=300)
                finally:
                    rr.delete('lock:' + HOT_KEY)
            else:
                with slock:
                    stats['waited'] += 1
                # 没拿到锁：短暂等待后重读缓存
                for _ in range(100):
                    time.sleep(0.01)
                    if rr.get(HOT_KEY) is not None:
                        return
                # 兜底：等待超时直接查 DB（生产应返回默认值或报错）
                with slock:
                    stats['db_direct'] += 1
                val = db.get(HOT_KEY)
                rr.set(HOT_KEY, val, ex=300)
        finally:
            rr.close()

    el, errs = run_concurrent(worker)
    print('拿到锁的线程数  : %d  ← 只有它查了 DB' % stats['lock_acquired'])
    print('等待后重读的    : %d' % stats['waited'])
    print('等待超时兜底    : %d' % stats['db_direct'])
    print('DB 查询次数     : %d' % db.queries)
    print('DB 瞬时最大并发 : %d' % db.max_concurrent)
    print('总耗时          : %.3f s' % el)
    print('错误            : %d' % len(errs))
    if errs:
        print('  ', errs[:3])
    print('最终缓存值      : %r' % r.get(HOT_KEY))
    r.close()
    return db.queries, db.max_concurrent


# =========================================================
# C. 逻辑过期
# =========================================================
def test_logic_expire():
    banner('C. 逻辑过期 —— key 物理不过期，value 内带 expire 时间戳')
    r = conn()
    r.flushdb()
    db = FakeDB(data={HOT_KEY: 'hot-value-v1'}, latency=DB_LATENCY)
    db.reset_stats()

    # 写入"已逻辑过期"的值：expire 时间戳设为过去
    import json
    past = time.time() - 1
    payload = json.dumps({'value': 'hot-value-v1', 'expire_at': past})
    r.set(HOT_KEY, payload)          # 注意：不设 EX，物理永不过期
    print('写入: SET %s {"value":"hot-value-v1","expire_at":<已过去 1 秒>}' % HOT_KEY)
    print('确认物理 TTL: %s（为 -1 表示永不过期）' % r.cmd('TTL', HOT_KEY))

    stats = {'refreshed': 0, 'served_stale': 0}
    slock = threading.Lock()

    def worker(tid):
        rr = conn()
        try:
            v = rr.get(HOT_KEY)
            if v is None:
                return
            obj = json.loads(v)
            if obj['expire_at'] > time.time():
                return                      # 逻辑未过期，直接返回
            # 逻辑已过期：抢锁刷新，抢不到就先返回旧值
            got = rr.set('lock:' + HOT_KEY, '1', ex=LOCK_TTL, nx=True)
            if got:
                with slock:
                    stats['refreshed'] += 1
                try:
                    val = db.get(HOT_KEY)
                    newp = json.dumps({'value': val,
                                       'expire_at': time.time() + LOGIC_TTL})
                    rr.set(HOT_KEY, newp)   # 仍然不设 EX
                finally:
                    rr.delete('lock:' + HOT_KEY)
            else:
                with slock:
                    stats['served_stale'] += 1
                # 返回旧数据（陈旧但可用），不阻塞
        finally:
            rr.close()

    el, errs = run_concurrent(worker)
    print('执行刷新的线程  : %d' % stats['refreshed'])
    print('返回旧值的线程  : %d  ← 全部立刻拿到数据，无等待' % stats['served_stale'])
    print('DB 查询次数     : %d' % db.queries)
    print('DB 瞬时最大并发 : %d' % db.max_concurrent)
    print('总耗时          : %.3f s  ← 没有任何线程阻塞等待' % el)
    print('错误            : %d' % len(errs))
    final = r.get(HOT_KEY)
    print('最终缓存值      : %s' % final[:80] if final else 'None')
    print('物理 TTL 仍为   : %s' % r.cmd('TTL', HOT_KEY))
    r.close()
    return db.queries, db.max_concurrent


# =========================================================
# D. 击穿 vs 穿透 的对照：key 存在且有值
# =========================================================
def test_control():
    banner('对照组：key 未过期时的正常命中（说明击穿是"过期那一瞬间"的问题）')
    r = conn()
    r.flushdb()
    db = FakeDB(data={HOT_KEY: 'hot-value-v1'}, latency=DB_LATENCY)
    db.reset_stats()
    r.set(HOT_KEY, db.data[HOT_KEY], ex=300)     # 未过期

    def worker(tid):
        rr = conn()
        try:
            v = rr.get(HOT_KEY)
            if v is None:
                db.get(HOT_KEY)
        finally:
            rr.close()

    el, errs = run_concurrent(worker)
    print('DB 查询次数     : %d  ← 全命中缓存，DB 零压力' % db.queries)
    print('总耗时          : %.3f s' % el)
    r.close()
    return db.queries


def main():
    print('实验参数：并发 %d 线程，DB 单次重建耗时 %.0f ms' % (CONC, DB_LATENCY * 1000))
    a_q, a_c = test_baseline()
    b_q, b_c = test_mutex()
    c_q, c_c = test_logic_expire()
    d_q = test_control()

    banner('汇总：热点 key 过期瞬间 %d 并发的 DB 压力' % CONC)
    print('%-22s %-12s %-14s %-10s' % ('方案', 'DB 查询次数', 'DB 瞬时并发', '是否阻塞请求'))
    print('-' * 64)
    print('%-22s %-12d %-14d %-10s' % ('A 无防护', a_q, a_c, '否（但 DB 被打爆）'))
    print('%-22s %-12d %-14d %-10s' % ('B 互斥锁 SET NX', b_q, b_c, '是（未获锁者等待）'))
    print('%-22s %-12d %-14d %-10s' % ('C 逻辑过期', c_q, c_c, '否（返回旧值）'))
    print('%-22s %-12d %-14d %-10s' % ('（对照）未过期', d_q, 0, '否'))


if __name__ == '__main__':
    main()
