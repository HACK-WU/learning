#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
定位疑问：扫描式冲刷场景下，
  allkeys-lru + samples=1  → 热key存活 1827/2000
  allkeys-random          → 热key存活  474/2000
两者都近似"随机淘汰"，为什么差距这么大？

假设：
  H1. samples=1 时淘汰效率低（每次只抽 1 个，且候选池复用），实际淘汰总数更少
  H2. samples=1 时淘汰的是"更早写入的冷 key"，而非随机
验证指标：淘汰总数、最终 dbsize、冷key存活数、热key存活数
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
HOT_N = 2000
N = 20000
VAL = 'x' * 100


def restart(policy, samples):
    os.system('redis-cli -p %d shutdown nosave 2>/dev/null' % PORT)
    time.sleep(0.3)
    os.system(' '.join([
        'redis-server', '--port', str(PORT),
        '--save', '', '--appendonly', 'no',
        '--dir', '/tmp/redis-l08', '--dbfilename', 'l08m.rdb',
        '--daemonize', 'yes', '--logfile', '/tmp/redis-l08/%d.log' % PORT,
        '--maxmemory', '2mb', '--maxmemory-policy', policy,
        '--maxmemory-samples', str(samples)]))
    for _ in range(80):
        try:
            r = Redis(port=PORT, timeout=1)
            r.cmd('PING')
            return r
        except Exception:
            time.sleep(0.1)
    raise RuntimeError('not up')


def run(policy, samples, seed=42):
    r = restart(policy, samples)
    r.flushdb()
    for i in range(HOT_N):
        r.set('k:%d' % i, VAL)
    random.seed(seed)
    for _ in range(HOT_N * 3):
        r.get('k:%d' % random.randrange(HOT_N))

    wrote = 0
    for i in range(HOT_N, N):
        try:
            r.set('k:%d' % i, VAL)
            wrote += 1
        except Exception:
            break

    hot = sum(1 for i in range(HOT_N) if r.exists('k:%d' % i))
    cold = sum(1 for i in range(HOT_N, N) if r.exists('k:%d' % i))
    evicted = int(r.info('stats').split('evicted_keys:')[1].split('\r\n')[0])
    dbsize = r.dbsize()
    used = r.info('memory').split('used_memory:')[1].split('\r\n')[0]
    r.close()
    return {'policy': policy, 'samples': samples, 'hot': hot, 'cold': cold,
            'wrote': wrote, 'evicted': evicted, 'dbsize': dbsize, 'used': used}


def main():
    print('=' * 84)
    print('扫描式冲刷：samples=1 与 allkeys-random 的差异定位')
    print('=' * 84)
    print('%-20s %-6s %-9s %-9s %-8s %-9s %-8s' %
          ('策略', 'samples', '热key存活', '冷key存活', '写入数', '淘汰数', 'dbsize'))
    print('-' * 84)
    for label, pol, s in [
        ('allkeys-lru', 'allkeys-lru', 1),
        ('allkeys-lru', 'allkeys-lru', 2),
        ('allkeys-lru', 'allkeys-lru', 3),
        ('allkeys-lru', 'allkeys-lru', 5),
        ('allkeys-random', 'allkeys-random', 5),
    ]:
        r = run(pol, s)
        print('%-20s %-6s %-9d %-9d %-8d %-9d %-8d' %
              (r['policy'], r['samples'], r['hot'], r['cold'],
               r['wrote'], r['evicted'], r['dbsize']))

    print()
    print('解读提示：')
    print('  - 若 samples=1 的"淘汰数"明显小于 random，说明它淘汰效率低（H1 成立）')
    print('  - 比较"热key存活 + 冷key存活"与 dbsize 是否吻合')

    os.system('redis-cli -p %d shutdown nosave 2>/dev/null' % PORT)
    print('\n7102 已关闭')


if __name__ == '__main__':
    main()
