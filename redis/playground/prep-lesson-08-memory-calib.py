#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8 内存实验：容量标定 + 改进后的淘汰策略横评。

修复的问题：
  1. maxmemory 设 8mb 时 20000 个 key 只占 3.91MB，从未触发淘汰 → 所有策略命中率都是 100%，
     实验无效。本脚本先"标定"出刚好容纳目标 key 数的内存量，再据此设置。
  2. 淘汰策略横评的顺序错了：必须先跑一轮访问让 LRU/LFU 建立访问统计，
     再在"持续访问中"逐步写入冷数据触发淘汰，否则 LRU 没有信息可用。

输出：供讲义直接引用的实测数据。
"""
import os
import time
import random
import importlib.util

_LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    'prep-lesson-08-lib.py')
_spec = importlib.util.spec_from_file_location('prep_lesson_08_lib', _LIB)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
Redis = _mod.Redis

PORT = 7102
N = 20000            # 总 key 数
HOT_N = 2000         # 热 key 数
VAL = 'x' * 100      # 每个 value 100 字节


def conn(port=PORT):
    return Redis(port=port)


def restart(port=PORT, maxmem=None, policy='noeviction', samples=5):
    os.system('redis-cli -p %d shutdown nosave 2>/dev/null' % port)
    time.sleep(0.3)
    args = ['redis-server', '--port', str(port),
            '--save', '', '--appendonly', 'no',
            '--dir', '/tmp/redis-l08', '--dbfilename', 'l08m.rdb',
            '--daemonize', 'yes', '--logfile', '/tmp/redis-l08/%d.log' % port]
    if maxmem:
        args += ['--maxmemory', maxmem]
    args += ['--maxmemory-policy', policy, '--maxmemory-samples', str(samples)]
    os.system(' '.join(args))
    for _ in range(80):
        try:
            r = Redis(port=port, timeout=1)
            r.cmd('PING')
            return r
        except Exception:
            time.sleep(0.1)
    raise RuntimeError('port %d not up' % port)


def calibrate(target_keys=N // 2):
    """二分/线性探测：找出刚好能容纳 target_keys 个 key 的 maxmemory（MB）。"""
    print('目标：找到刚好能容纳约 %d 个 key（占总量一半）的 maxmemory' % target_keys)
    lo, hi = 1, 64
    best = None
    for mb in [2, 3, 4, 5, 6, 8, 10, 12, 16]:
        r = restart(PORT, maxmem='%dmb' % mb, policy='allkeys-lru')
        r.flushdb()
        wrote = 0
        for i in range(N):
            try:
                r.set('k:%d' % i, VAL)
                wrote += 1
            except Exception:
                break
        used = r.info('memory').split('used_memory:')[1].split('\r\n')[0]
        evicted = int(r.info('stats').split('evicted_keys:')[1].split('\r\n')[0])
        print('  maxmemory=%2dmb → 实际写入 %5d 个 key，淘汰 %5d 个，used_memory=%s'
              % (mb, wrote, evicted, used))
        r.close()
        if abs(wrote - target_keys) <= target_keys * 0.15:
            best = mb
            print('  ↑ 命中目标区间，选定 maxmemory=%dmb' % mb)
            break
        if wrote > target_keys:
            best = best or mb
    if best is None:
        best = 4
        print('  未精确命中，回落使用 %dmb' % best)
    return best


def run_policy(pol, maxmem_mb, samples=5, give_ttl_to_cold=True, seed=42):
    """
    正确的横评流程：
      1. 先写满热 key 并访问它们（建立 LRU/LFU 统计）
      2. 再写入冷 key，触发淘汰
      3. 最后按 Zipf 分布访问，测命中率
    """
    r = restart(PORT, maxmem='%dmb' % maxmem_mb, policy=pol, samples=samples)
    r.flushdb()

    volatile = pol.startswith('volatile')

    # 阶段 1：写入热 key + 访问（建立访问统计）
    for i in range(HOT_N):
        r.set('k:%d' % i, VAL)
    random.seed(seed)
    for _ in range(HOT_N * 3):
        r.get('k:%d' % random.randrange(HOT_N))
    hot_survive_1 = sum(1 for i in range(HOT_N) if r.exists('k:%d' % i))

    # 阶段 2：写入冷 key 触发淘汰
    wrote_cold = 0
    for i in range(HOT_N, N):
        try:
            if volatile and give_ttl_to_cold:
                r.set('k:%d' % i, VAL, ex=3600)     # 冷 key 带 TTL
            else:
                r.set('k:%d' % i, VAL)
            wrote_cold += 1
        except Exception:
            break

    # 阶段 3：热 key 还剩多少？（关键指标）
    hot_survive_2 = sum(1 for i in range(HOT_N) if r.exists('k:%d' % i))

    # 阶段 4：Zipf 访问测命中率
    random.seed(seed)
    hit = miss = 0
    for _ in range(20000):
        k = ('k:%d' % random.randrange(HOT_N)) if random.random() < 0.8 \
            else ('k:%d' % random.randrange(HOT_N, N))
        if r.get(k) is not None:
            hit += 1
        else:
            miss += 1

    evicted = int(r.info('stats').split('evicted_keys:')[1].split('\r\n')[0])
    dbsize = r.dbsize()
    rate = hit * 100.0 / (hit + miss) if (hit + miss) else 0
    r.close()
    return {
        'policy': pol, 'maxmem_mb': maxmem_mb, 'samples': samples,
        'hot_after_access': hot_survive_1, 'hot_after_cold': hot_survive_2,
        'cold_written': wrote_cold, 'dbsize': dbsize,
        'hit': hit, 'miss': miss, 'rate': rate, 'evicted': evicted,
    }


def main():
    print('=' * 78)
    print('步骤 1：容量标定（确保 maxmemory 真的会触发淘汰）')
    print('=' * 78)
    mb = calibrate()
    print('\n选定 maxmemory = %dmb\n' % mb)

    print('=' * 78)
    print('步骤 2：8 种策略横评（先建立访问统计，再写冷数据触发淘汰）')
    print('=' * 78)
    print('关键指标说明：')
    print('  - 热key存活: 写入冷数据后，2000 个热 key 还剩多少个（越高说明策略越聪明）')
    print('  - 命中率: 之后按 Zipf 分布访问 20000 次的缓存命中率')
    print()
    policies = ['noeviction', 'allkeys-lru', 'volatile-lru', 'allkeys-lfu',
                'volatile-lfu', 'allkeys-random', 'volatile-random', 'volatile-ttl']
    results = []
    for pol in policies:
        res = run_policy(pol, mb)
        results.append(res)
        print('%-16s 热key存活 %4d/2000  冷key写入 %5d  最终dbsize %5d  '
              '命中率 %5.1f%%  淘汰数 %6d'
              % (pol, res['hot_after_cold'], res['cold_written'],
                 res['dbsize'], res['rate'], res['evicted']))

    print('\n' + '=' * 78)
    print('步骤 3：maxmemory-samples 对 LRU 精度的影响')
    print('=' * 78)
    for s in [1, 3, 5, 10, 20, 50]:
        res = run_policy('allkeys-lru', mb, samples=s)
        print('samples=%-3d → 热key存活 %4d/2000，命中率 %5.1f%%'
              % (s, res['hot_after_cold'], res['rate']))

    print('\n' + '=' * 78)
    print('步骤 4：volatile-* 无 TTL 时的退化陷阱（不设 TTL 的冷 key）')
    print('=' * 78)
    for pol in ['volatile-lru', 'allkeys-lru']:
        r = restart(PORT, maxmem='4mb', policy=pol)
        r.flushdb()
        ok, err, msg = 0, 0, None
        for i in range(200000):
            try:
                r.set('nt:%d' % i, VAL)
                ok += 1
            except Exception as e:
                err += 1
                msg = str(e) if msg is None else msg
                if err >= 5:
                    break
        print('%-16s 写入成功 %6d 次，失败 %3d 次 %s'
              % (pol, ok, err, ('报错: ' + msg) if msg else ''))
        r.close()

    os.system('redis-cli -p %d shutdown nosave 2>/dev/null' % PORT)
    print('\n7102 已关闭')


if __name__ == '__main__':
    main()
