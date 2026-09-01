#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8 LRU / LFU 公平对照实验。

背景：prep-lesson-08-memory-calib.py 的横评里 allkeys-lru 表现极差（热 key 存活 25/2000，
命中率 9.4%），甚至不如 allkeys-random。原因是那个测试"先写热 key 并访问，然后
一次性灌入 18000 个冷 key"——在 LRU 语义下正确，但制造了一次罕见的"扫描式冲刷"：
大量新 key 一次性涌入，把 LRU 链表整个挤掉。这是 LRU 的真实弱点（一次全表扫描
就能污染整个缓存），但用它来比较策略优劣并不公平。

本脚本补两组更贴近真实业务的对照：
  场景 A（扫描式冲刷）：一次性灌入大量冷 key —— 复现 LRU 的弱点
  场景 B（稳定负载）：读写交替进行，更接近真实线上流量
  场景 C（LFU 抗扫描）：同样扫描式冲刷，但用 LFU —— 验证 LFU 的抗污染能力

并直接观测 OBJECT IDLETIME / OBJECT FREQ 看 Redis 内部到底记了什么。
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
VAL = 'x' * 100
MAXMEM_MB = 2          # 与标定结果一致：2mb 下会触发淘汰


def restart(port=PORT, maxmem='%dmb' % MAXMEM_MB, policy='allkeys-lru', samples=5):
    os.system('redis-cli -p %d shutdown nosave 2>/dev/null' % port)
    time.sleep(0.3)
    os.system(' '.join([
        'redis-server', '--port', str(port),
        '--save', '', '--appendonly', 'no',
        '--dir', '/tmp/redis-l08', '--dbfilename', 'l08m.rdb',
        '--daemonize', 'yes', '--logfile', '/tmp/redis-l08/%d.log' % port,
        '--maxmemory', maxmem, '--maxmemory-policy', policy,
        '--maxmemory-samples', str(samples)]))
    for _ in range(80):
        try:
            r = Redis(port=port, timeout=1)
            r.cmd('PING')
            return r
        except Exception:
            time.sleep(0.1)
    raise RuntimeError('port %d not up' % port)


def zipf_get(r, n, hot_n=HOT_N, hot_ratio=0.8, seed=42):
    random.seed(seed)
    hit = 0
    for _ in range(n):
        k = ('k:%d' % random.randrange(hot_n)) if random.random() < hot_ratio \
            else ('k:%d' % random.randrange(hot_n, hot_n * 9))
        if r.get(k) is not None:
            hit += 1
    return hit


def hot_survive(r, hot_n=HOT_N):
    return sum(1 for i in range(hot_n) if r.exists('k:%d' % i))


def scenario_scan(policy, cold_n=18000, samples=5):
    """场景 A：先建立热点，再一次性灌入大量冷 key（扫描式冲刷）。"""
    r = restart(PORT, policy=policy, samples=samples)
    r.flushdb()
    for i in range(HOT_N):
        r.set('k:%d' % i, VAL)
    random.seed(42)
    for _ in range(HOT_N * 3):
        r.get('k:%d' % random.randrange(HOT_N))
    hot0 = hot_survive(r)
    wrote = 0
    for i in range(HOT_N, HOT_N + cold_n):
        try:
            r.set('k:%d' % i, VAL, ex=3600) if policy.startswith('volatile') \
                else r.set('k:%d' % i, VAL)
            wrote += 1
        except Exception:
            break
    hot1 = hot_survive(r)
    hit = zipf_get(r, 20000)
    r.close()
    return hot0, hot1, hit * 100.0 / 20000, wrote


def scenario_steady(policy, rounds=30, per_round=600, samples=5):
    """场景 B：读写交替的稳定负载（更接近真实线上流量）。"""
    r = restart(PORT, policy=policy, samples=samples)
    r.flushdb()
    for i in range(HOT_N):
        r.set('k:%d' % i, VAL)
    random.seed(42)
    # 交替：访问一批 → 写入一批冷 key → 再访问……
    cold_idx = HOT_N
    for rd in range(rounds):
        for _ in range(per_round):
            r.get('k:%d' % random.randrange(HOT_N))         # 持续访问热 key
        for _ in range(per_round // 3):                     # 缓慢写入冷 key
            try:
                if policy.startswith('volatile'):
                    r.set('k:%d' % cold_idx, VAL, ex=3600)
                else:
                    r.set('k:%d' % cold_idx, VAL)
                cold_idx += 1
            except Exception:
                pass
    hot1 = hot_survive(r)
    hit = zipf_get(r, 20000)
    r.close()
    return hot1, hit * 100.0 / 20000


def probe_internals():
    """直接看 Redis 内部为 LRU / LFU 记录了什么。"""
    print('=' * 76)
    print('观测 Redis 内部度量：OBJECT IDLETIME（LRU）与 OBJECT FREQ（LFU）')
    print('=' * 76)

    r = restart(PORT, policy='allkeys-lru')
    r.flushdb()
    r.cmd('SET', 'probe:hot', 'v')
    r.cmd('SET', 'probe:cold', 'v')
    for _ in range(50):
        r.cmd('GET', 'probe:hot')
    time.sleep(1.2)
    print('LRU 模式下（CONFIG maxmemory-policy=allkeys-lru）：')
    print('  probe:hot  （访问 50 次）OBJECT IDLETIME = %s 秒'
          % r.cmd('OBJECT', 'IDLETIME', 'probe:hot'))
    print('  probe:cold （未访问）    OBJECT IDLETIME = %s 秒'
          % r.cmd('OBJECT', 'IDLETIME', 'probe:cold'))
    print('  → IDLETIME 是"距上次访问的空闲秒数"，LRU 淘汰时选空闲最久的')
    print('  注意：这个时钟只有 24 位（精度有限，最大值约 194 天）')
    r.close()

    r = restart(PORT, policy='allkeys-lfu')
    r.flushdb()
    r.cmd('SET', 'probe:hot', 'v')
    r.cmd('SET', 'probe:cold', 'v')
    for _ in range(200):
        r.cmd('GET', 'probe:hot')
    print('\nLFU 模式下（CONFIG maxmemory-policy=allkeys-lfu）：')
    print('  probe:hot  （访问 200 次）OBJECT FREQ = %s'
          % r.cmd('OBJECT', 'FREQ', 'probe:hot'))
    print('  probe:cold （未访问）    OBJECT FREQ = %s'
          % r.cmd('OBJECT', 'FREQ', 'probe:cold'))
    print('  → FREQ 不是访问次数，是 0~255 的对数计数器（Morris 计数器）')
    print('  相关配置：lfu-log-factor=%s（越大，升到高 FREQ 越难）'
          % (r.config_get('lfu-log-factor')[1] if
             isinstance(r.config_get('lfu-log-factor'), list) else '?'))
    print('            lfu-decay-time=%s（分钟，多久没访问就衰减）'
          % (r.config_get('lfu-decay-time')[1] if
             isinstance(r.config_get('lfu-decay-time'), list) else '?'))
    print('  新 key 初始 FREQ=5（不是 0），避免刚写入就被淘汰')
    r.close()


def main():
    probe_internals()

    print('\n' + '=' * 76)
    print('场景 A：扫描式冲刷 —— 先建热点，再一次性灌入 18000 个冷 key')
    print('（这是 LRU 的真实弱点：一次全表扫描就能把缓存冲干净）')
    print('=' * 76)
    print('%-16s %-14s %-10s' % ('策略', '热key存活', '命中率'))
    print('-' * 76)
    for pol in ['allkeys-lru', 'allkeys-lfu', 'allkeys-random']:
        h0, h1, rate, wrote = scenario_scan(pol)
        print('%-16s %-14s %-10s' % (pol, '%d/2000' % h1, '%.1f%%' % rate))

    print('\n' + '=' * 76)
    print('场景 B：稳定负载 —— 读写交替 30 轮（更接近真实线上流量）')
    print('=' * 76)
    print('%-16s %-14s %-10s' % ('策略', '热key存活', '命中率'))
    print('-' * 76)
    for pol in ['allkeys-lru', 'allkeys-lfu', 'allkeys-random']:
        h1, rate = scenario_steady(pol)
        print('%-16s %-14s %-10s' % (pol, '%d/2000' % h1, '%.1f%%' % rate))

    print('\n' + '=' * 76)
    print('结论提示（供讲义引用）')
    print('=' * 76)
    print('1. 场景 A 里 LRU 差，不是 LRU 算法差，而是"一次性灌入大量新 key"这个动作')
    print('   恰好命中 LRU 的弱点：新 key 都是最新访问的，会把老的热数据挤出去')
    print('2. LFU 在这种场景下更稳，因为它看的是"历史访问频次"而非"最近一次访问时间"')
    print('3. 场景 B 更接近真实业务，读写交替时 LRU 的表现会明显回升')

    os.system('redis-cli -p %d shutdown nosave 2>/dev/null' % PORT)
    print('\n7102 已关闭')


if __name__ == '__main__':
    main()
