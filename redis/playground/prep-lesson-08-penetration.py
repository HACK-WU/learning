#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8 知识点 1（穿透部分）实测：缓存穿透的三种解法对照。

三组实验：
  A. 无防护基线      —— 查询不存在的 id，全部打到 DB
  B. 缓存空值        —— DB 未命中时写 NULL 占位 + 短 TTL
  C. 布隆过滤器      —— 前置 BF.EXISTS 拦截（Redis 8 内置 bf 模块）

度量指标：DB 查询次数、DB 瞬时最大并发 —— 穿透的危害体现在这里。
"""
import os
import sys
import time
import random
import importlib.util

# 基座文件名带连字符，无法用普通 import，按文件路径加载
_LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    'prep-lesson-08-lib.py')
_spec = importlib.util.spec_from_file_location('prep_lesson_08_lib', _LIB)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
Redis, FakeDB = _mod.Redis, _mod.FakeDB

PORT = 7101
N = 2000                      # 攻击请求数
EXIST_N = 500                 # 真实存在的 id 数量
NULL_TTL = 10                 # 空值缓存 TTL（秒）
DB_LATENCY = 0.002            # DB 单次查询 2ms


def banner(t):
    print('\n' + '=' * 62)
    print(t)
    print('=' * 62)


def build_db():
    """真实数据：id 1..EXIST_N 存在，其余不存在。"""
    return FakeDB(data={i: 'user-%d' % i for i in range(1, EXIST_N + 1)},
                  latency=DB_LATENCY)


def attack_ids(n):
    """攻击者只打不存在的 id：从远大于真实范围的区间随机取。"""
    return [random.randint(1000000, 9999999) for _ in range(n)]


def run(r, db, ids, mode):
    """按给定模式处理一批请求，返回 (命中缓存数, DB 查询数)。"""
    cache_hits = 0
    before = db.queries
    for i in ids:
        key = 'user:%d' % i
        if mode == 'baseline':
            v = r.get(key)
            if v is not None:
                cache_hits += 1
            else:
                db.get(i)
        elif mode == 'null':
            v = r.get(key)
            if v is not None:
                cache_hits += 1
                if v == '__NULL__':
                    continue          # 空值占位也算"挡住了"
            else:
                val = db.get(i)
                if val is None:
                    r.set(key, '__NULL__', ex=NULL_TTL)
                else:
                    r.set(key, val, ex=300)
        elif mode == 'bloom':
            # 布隆前置拦截：不存在直接返回，不查 DB 也不查缓存
            if not r.cmd('BF.EXISTS', 'user:bloom', str(i)):
                continue
            v = r.get(key)
            if v is not None:
                cache_hits += 1
            else:
                val = db.get(i)
                if val is not None:
                    r.set(key, val, ex=300)
    return cache_hits, db.queries - before


def main():
    r = Redis(port=PORT)
    r.flushdb()

    # ---------- 预热：把真实数据写进缓存 ----------
    db = build_db()
    for i in range(1, EXIST_N + 1):
        r.set('user:%d' % i, db.data[i], ex=300)
    print('预热完成：缓存中已有 %d 个真实用户（观察到预热 DB 查询 %d 次）'
          % (r.dbsize(), db.queries))

    ids = attack_ids(N)

    # ================= A. 基线 =================
    banner('A. 无防护基线 —— 攻击者专打不存在的 id')
    db = build_db()
    db.reset_stats()
    t0 = time.time()
    hits, q = run(r, db, ids, 'baseline')
    el = time.time() - t0
    print('攻击请求数      : %d' % N)
    print('缓存命中        : %d' % hits)
    print('DB 查询次数     : %d' % q)
    print('DB 瞬时最大并发 : %d' % db.max_concurrent)
    print('耗时            : %.2f s' % el)
    print('结论：不存在的 key 每次都穿透到 DB，缓存完全失效')

    baseline_q = q

    # ================= B. 缓存空值 =================
    banner('B. 缓存空值 —— DB 未命中时写 NULL 占位（TTL=%ds）' % NULL_TTL)
    r.flushdb()
    db = build_db()
    db.reset_stats()
    for i in range(1, EXIST_N + 1):
        r.set('user:%d' % i, db.data[i], ex=300)
    db.reset_stats()

    t0 = time.time()
    hits, q = run(r, db, ids, 'null')
    el = time.time() - t0
    print('第 1 轮（%d 个不同 id，首次全部穿透）：' % N)
    print('  DB 查询次数 : %d' % q)
    print('  缓存命中    : %d' % hits)
    print('  耗时        : %.2f s' % el)

    # 第二轮：同样的 id 再来一次（模拟攻击者重复打同一批 id）
    db.reset_stats()
    t0 = time.time()
    hits, q2 = run(r, db, ids, 'null')
    el2 = time.time() - t0
    print('第 2 轮（重复打相同 id）：')
    print('  DB 查询次数 : %d  ← 已被空值占位挡住' % q2)
    print('  缓存命中    : %d' % hits)
    print('  耗时        : %.3f s' % el2)

    print('缓存 key 总数    : %d（真实 %d + 空值占位 %d）'
          % (r.dbsize(), EXIST_N, r.dbsize() - EXIST_N))
    r.config_set('maxmemory', '0')
    mem = r.info('memory')
    print('内存占用        : %s' % mem.split('used_memory_human:')[1].split('\r\n')[0])
    print('结论：空值挡住"重复打同一批 id"，但随机 id 攻击仍全部穿透（第 1 轮 %d 次）' % q)

    # ================= C. 布隆过滤器 =================
    banner('C. 布隆过滤器 —— Redis 8 内置 bf 模块前置拦截')
    r.flushdb()
    db = build_db()
    db.reset_stats()

    # 建过滤器：误判率 0.1%，预期 500 个元素
    print('创建过滤器: BF.RESERVE user:bloom 0.001 500')
    r.cmd('BF.RESERVE', 'user:bloom', '0.001', str(EXIST_N))
    for i in range(1, EXIST_N + 1):
        r.cmd('BF.ADD', 'user:bloom', str(i))
    print('已加入 %d 个真实 id' % EXIST_N)

    minfo = r.cmd('BF.INFO', 'user:bloom')
    print('BF.INFO 输出（过滤器参数）：')
    if isinstance(minfo, list):
        it = iter(minfo)
        for k, v in zip(it, it):
            print('  %-16s %s' % (k, v))
    else:
        print(' ', minfo)

    # 预热真实数据到缓存
    for i in range(1, EXIST_N + 1):
        r.set('user:%d' % i, db.data[i], ex=300)
    db.reset_stats()

    t0 = time.time()
    hits, q = run(r, db, ids, 'bloom')
    el = time.time() - t0
    print('攻击请求数      : %d' % N)
    print('DB 查询次数     : %d  ← 只有误判的才穿透' % q)
    print('缓存命中        : %d' % hits)
    print('耗时            : %.3f s' % el)

    # 误判率实测：拿 50000 个确定不存在的 id 直接测 BF.EXISTS
    fp_probe = 50000
    fp = 0
    for i in range(90000000, 90000000 + fp_probe):
        if r.cmd('BF.EXISTS', 'user:bloom', str(i)):
            fp += 1
    print('误判率实测      : %d / %d = %.4f%%（声明 0.1%%）'
          % (fp, fp_probe, fp * 100.0 / fp_probe))

    # 正常请求是否被误伤：存在的 id 必须 100% 放行
    fn = 0
    for i in range(1, EXIST_N + 1):
        if not r.cmd('BF.EXISTS', 'user:bloom', str(i)):
            fn += 1
    print('存在的 id 被拦  : %d / %d = %.2f%%  ← 布隆不会漏报（假阴性为 0）'
          % (fn, EXIST_N, fn * 100.0 / EXIST_N))

    sz = r.cmd('MEMORY', 'USAGE', 'user:bloom')
    print('过滤器内存      : %d 字节（%.2f KB），存 %d 个 id'
          % (sz, sz / 1024.0, EXIST_N))
    print('平均每 id 开销  : %.2f 字节' % (sz / EXIST_N))

    # ================= 汇总 =================
    banner('汇总：三种方案在 %d 次随机不存在 id 攻击下的 DB 压力' % N)
    print('%-14s %-16s %-16s' % ('方案', 'DB 查询次数', '说明'))
    print('-' * 62)
    print('%-14s %-16s %-16s' % ('无防护', baseline_q, '全穿透'))
    print('%-14s %-16s %-16s' % ('缓存空值(首轮)', N, '随机 id 仍全穿透'))
    print('%-14s %-16s %-16s' % ('缓存空值(重复)', 0, '同 id 可挡住'))
    print('%-14s %-16s %-16s' % ('布隆过滤器', q, '仅误判穿透'))

    r.close()


if __name__ == '__main__':
    main()
