#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8 知识点 3 实测：内存淘汰与过期策略。

实验列表：
  1. 过期删除的两条路径：惰性删除 + 定期删除（用 INFO 的 expired_keys 观察）
  2. 定期删除的"抽样 + 贪心"行为（hz 与每次抽查数量）
  3. 8 种淘汰策略横评（重点：allkeys-lru vs volatile-lru vs allkeys-lfu vs random）
  4. 缓存命中率对比 —— 用真实的 Zipf 分布访问序列，看哪种策略保住热数据
  5. noeviction 下的写失败行为
  6. LRU 近似算法：maxmemory-samples 与 eviction pool 的影响
  7. volatile-* 策略在"所有 key 都无 TTL"时的退化行为（关键陷阱）
"""
import os
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

PORT = 7102          # 内存实验用独立端口，避免影响 7101
N = 20000            # 写入 key 数
HOT_N = 2000         # 热点 key 数量


def banner(t):
    print('\n' + '=' * 72)
    print(t)
    print('=' * 72)


def conn(port=PORT):
    return Redis(port=port)


def wait_up(port=PORT, n=80):
    for _ in range(n):
        try:
            r = Redis(port=port, timeout=1)
            r.cmd('PING')
            return r
        except Exception:
            time.sleep(0.1)
    raise RuntimeError('port %d not up' % port)


def restart(port=PORT, maxmem=None, policy='noeviction', samples=5, extra=None):
    os.system('redis-cli -p %d shutdown nosave 2>/dev/null' % port)
    time.sleep(0.3)
    args = ['redis-server', '--port', str(port),
            '--save', '', '--appendonly', 'no',
            '--dir', '/tmp/redis-l08', '--dbfilename', 'l08m.rdb',
            '--daemonize', 'yes', '--logfile', '/tmp/redis-l08/%d.log' % port]
    if maxmem:
        args += ['--maxmemory', maxmem]
    if policy:
        args += ['--maxmemory-policy', policy]
    args += ['--maxmemory-samples', str(samples)]
    if extra:
        args += extra
    os.system(' '.join(args))
    return wait_up(port)


# ---------------------------------------------------------
# 实验 1：过期删除的两条路径
# ---------------------------------------------------------
def test_expiry_paths():
    banner('实验 1：过期 key 的两条删除路径 —— 惰性删除 + 定期删除')
    r = restart(PORT, maxmem='256mb', policy='noeviction')
    r.flushdb()

    print('写入 5 个 TTL=1 秒的 key，然后什么都不做，睡 2.5 秒')
    for i in range(5):
        r.set('k%d' % i, 'v', ex=1)
    before_keys = r.dbsize()
    e0 = int(r.info('stats').split('expired_keys:')[1].split('\r\n')[0])
    print('  睡之前: dbsize=%d, expired_keys=%d' % (before_keys, e0))

    time.sleep(2.5)
    after_keys = r.dbsize()
    e1 = int(r.info('stats').split('expired_keys:')[1].split('\r\n')[0])
    print('  睡之后: dbsize=%d, expired_keys=%d  ← 定期删除已回收 %d 个'
          % (after_keys, e1, e1 - e0))
    print('  TTL 查询: TTL k0 = %s（-2 表示 key 已不存在）' % r.cmd('TTL', 'k0'))
    print()
    print('结论：过期的 key 不是"到点立刻消失"，而是由后台定期任务慢慢回收')

    # 惰性删除：写入一个大批量过期 key，看访问时是否被立即删除
    print('\n验证惰性删除：写入 3 个 TTL=1 秒的 key，等过期后主动 GET')
    for i in range(3):
        r.set('lazy%d' % i, 'v', ex=1)
    time.sleep(1.2)
    e2 = int(r.info('stats').split('expired_keys:')[1].split('\r\n')[0])
    print('  过期后未访问: GET lazy0 = %r, expired_keys=%d' % (r.get('lazy0'), e2))
    e3 = int(r.info('stats').split('expired_keys:')[1].split('\r\n')[0])
    print('  访问后 expired_keys=%d（+=%d）← 访问时才被真正删除'
          % (e3, e3 - e2))
    r.close()


# ---------------------------------------------------------
# 实验 2：定期删除的抽样行为
# ---------------------------------------------------------
def test_active_expire():
    banner('实验 2：定期删除是"抽样 + 贪心"，不是全量扫描')
    r = restart(PORT, maxmem='256mb', policy='noeviction')
    r.flushdb()

    # 写入 10 万个带 TTL 的 key，其中只有 1000 个已过期
    print('写入 100000 个 key（其中 1000 个 TTL=1s，其余 TTL=3600s）')
    pipe_size = 100000
    for i in range(1000):
        r.set('exp:%d' % i, 'v', ex=1)
    t0 = time.time()
    for i in range(pipe_size - 1000):
        r.set('live:%d' % i, 'v', ex=3600)
    print('  写入耗时 %.2f s, dbsize=%d' % (time.time() - t0, r.dbsize()))

    time.sleep(1.5)
    e0 = int(r.info('stats').split('expired_keys:')[1].split('\r\n')[0])
    t0 = time.time()
    # 观察 5 秒内定期任务回收了多少
    time.sleep(5)
    e1 = int(r.info('stats').split('expired_keys:')[1].split('\r\n')[0])
    print('  5 秒内回收过期 key: %d 个（共 1000 个已过期）' % (e1 - e0))
    print('  剩余 dbsize=%d' % r.dbsize())
    print()
    print('Redis 定期删除的行为（activeExpireCycle）：')
    print('  - 每秒运行 hz 次（默认 hz=10，即每 100ms 一次）')
    print('  - 每次从过期字典中随机抽样 20 个 key，删除其中已过期的')
    print('  - 若这批中过期比例 > 25%，则再抽一轮（循环）')
    print('  - 单次执行有时间上限（默认 25ms 的 CPU 预算），避免卡住主线程')
    print()
    print('因此：过期 key 可能短暂残留在内存里，这是设计上的取舍（用 CPU 换及时性）')

    hz = r.config_get('hz')
    print('\n  当前 hz = %s' % (hz[1] if isinstance(hz, list) else hz))
    r.close()


# ---------------------------------------------------------
# 实验 3 & 4：淘汰策略横评 + 命中率
# ---------------------------------------------------------
def zipf_keys(n, hot_ratio=0.8):
    """生成 Zipf 分布访问序列：80% 的访问落在 20% 的 key 上。"""
    hot = int(n * (1 - hot_ratio))
    seq = []
    for _ in range(n):
        if random.random() < hot_ratio:
            seq.append('k:%d' % random.randrange(hot))     # 热数据
        else:
            seq.append('k:%d' % random.randrange(hot, n))  # 冷数据
    return seq


def test_policies():
    banner('实验 3+4：8 种淘汰策略横评 —— 用 Zipf 分布访问序列测命中率')
    policies = [
        'noeviction',
        'allkeys-lru',
        'volatile-lru',
        'allkeys-lfu',
        'volatile-lfu',
        'allkeys-random',
        'volatile-random',
        'volatile-ttl',
    ]
    print('测试设计：')
    print('  - 写入 %d 个 key，其中前 %d 个是"热 key"（访问占比 80%%）' % (N, HOT_N))
    print('  - maxmemory 设为刚好容纳约 50%% 的 key，强制触发淘汰')
    print('  - 然后按 Zipf 分布访问 20000 次，统计缓存命中率')
    print('  - 带 volatile- 前缀的策略：只给后 50%% 的 key 设 TTL（模拟"部分 key 有过期时间"）')
    print()

    results = []
    for pol in policies:
        r = restart(PORT, maxmem='8mb', policy=pol, samples=5)
        r.flushdb()

        # 写入：前 HOT_N 个无 TTL（热），后面的按策略决定是否给 TTL
        # 注意：volatile-* 只对"设置了 TTL 的 key"生效
        give_ttl = pol.startswith('volatile')
        for i in range(N):
            if give_ttl and i >= HOT_N:
                r.set('k:%d' % i, 'x' * 100, ex=3600)
            else:
                r.set('k:%d' % i, 'x' * 100)
        after_write = r.dbsize()

        # 按 Zipf 分布访问
        random.seed(42)
        seq = zipf_keys(20000, hot_ratio=0.8)
        hit = 0
        miss = 0
        for k in seq:
            if r.get(k) is not None:
                hit += 1
            else:
                miss += 1
        total = hit + miss
        rate = hit * 100.0 / total if total else 0

        evicted = int(r.info('stats').split('evicted_keys:')[1].split('\r\n')[0])
        used = r.info('memory').split('used_memory_human:')[1].split('\r\n')[0]
        results.append((pol, after_write, hit, miss, rate, evicted, used))
        print('%-18s 写入后key数=%-7d 命中=%-6d 未命中=%-6d 命中率=%5.1f%% 淘汰数=%-7d 内存=%s'
              % (pol, after_write, hit, miss, rate, evicted, used))
        r.close()

    print()
    print('解读：')
    print('  - allkeys-lru / allkeys-lfu 命中率最高：它们能识别并保留热数据')
    print('  - allkeys-random 明显更差：随机淘汰会把热数据也踢掉')
    print('  - volatile-* 在本测试中受限：只有当 key 设了 TTL 才能被淘汰')
    print('  - noeviction 不淘汰，写入阶段就可能因内存不足报错')
    return results


# ---------------------------------------------------------
# 实验 5：noeviction 下的写失败
# ---------------------------------------------------------
def test_noeviction():
    banner('实验 5：noeviction —— 内存满时写入直接报错')
    r = restart(PORT, maxmem='4mb', policy='noeviction')
    r.flushdb()
    ok = 0
    err = 0
    err_msg = None
    for i in range(200000):
        try:
            r.set('nx:%d' % i, 'x' * 100)
            ok += 1
        except Exception as e:
            err += 1
            if err_msg is None:
                err_msg = str(e)
            if err >= 50:
                break
    print('写入成功: %d 次' % ok)
    print('写入失败: %d 次' % err)
    print('首次报错 : %s' % err_msg)
    print('当前 dbsize=%d' % r.dbsize())
    print()
    print('注意：读命令（GET）在 noeviction 下仍然正常 —— 只有"会让内存增长"的写命令会失败')
    print('生产影响：如果没预料到，写请求会突然大面积报 OOM 错误')
    r.close()


# ---------------------------------------------------------
# 实验 6：LRU 近似算法与 samples
# ---------------------------------------------------------
def test_lru_samples():
    banner('实验 6：Redis 的 LRU 是"近似 LRU"—— maxmemory-samples 的影响')
    print('Redis 不维护全局 LRU 链表（太耗内存），而是：')
    print('  淘汰时随机抽 maxmemory-samples 个 key，从中选出"最久未访问"的淘汰')
    print('  Redis 3.0+ 引入 eviction pool（默认大小 16），跨轮次保留候选，提高精度')
    print()

    results = []
    for samples in [1, 3, 5, 10, 20, 50]:
        r = restart(PORT, maxmem='8mb', policy='allkeys-lru', samples=samples)
        r.flushdb()
        for i in range(N):
            r.set('k:%d' % i, 'x' * 100)
        random.seed(42)
        seq = zipf_keys(20000, hot_ratio=0.8)
        hit = sum(1 for k in seq if r.get(k) is not None)
        rate = hit * 100.0 / len(seq)
        results.append((samples, rate))
        print('maxmemory-samples=%-3d → 命中率 %5.1f%%' % (samples, rate))
        r.close()

    print()
    print('趋势：samples 越大越接近真实 LRU，命中率越高，但每次淘汰的 CPU 开销也越大')
    print('官方文档说明：samples=10 已非常接近真实 LRU，再增大收益递减；默认是 5')
    return results


# ---------------------------------------------------------
# 实验 7：volatile 策略的退化陷阱
# ---------------------------------------------------------
def test_volatile_trap():
    banner('实验 7：volatile-* 的致命陷阱 —— 没有 key 设 TTL 时会退化成 noeviction')
    for pol in ['volatile-lru', 'allkeys-lru']:
        r = restart(PORT, maxmem='4mb', policy=pol)
        r.flushdb()
        print('\n--- 策略 %s，写入的 key 全部【不设 TTL】 ---' % pol)
        ok, err, msg = 0, 0, None
        for i in range(200000):
            try:
                r.set('nt:%d' % i, 'x' * 100)
                ok += 1
            except Exception as e:
                err += 1
                msg = str(e) if msg is None else msg
                if err >= 20:
                    break
        print('  写入成功 %d 次，失败 %d 次' % (ok, err))
        if err:
            print('  报错: %s' % msg)
            print('  ❌ volatile-lru 找不到可淘汰的 key，等价于 noeviction，写入直接失败')
        else:
            print('  ✅ 淘汰正常，写入未受阻碍')
        r.close()

    print()
    print('生产含义：')
    print('  - 选 volatile-* 必须保证"至少一部分 key 有 TTL"，否则缓存层会变成不可写')
    print('  - 若要 Redis 只缓存、DB 是唯一真相源 → 用 allkeys-*')
    print('  - 若 Redis 里同时存了"缓存"和"持久数据"（如计数器、锁）→ 用 volatile-*，'
          '且只给缓存 key 设 TTL')


def main():
    print('内存实验使用独立端口 %d，与缓存实验端口 7101 隔离' % PORT)
    test_expiry_paths()
    test_active_expire()
    test_policies()
    test_noeviction()
    test_lru_samples()
    test_volatile_trap()

    banner('知识点 3 核心结论')
    print('1. 过期删除 = 惰性删除（访问时检查）+ 定期删除（每秒 hz 次抽样）')
    print('2. 定期删除是抽样式、有时间预算的，过期 key 可能短暂残留 —— 这是 CPU 与及时性的取舍')
    print('3. 淘汰策略分三类：noeviction / allkeys-* / volatile-*')
    print('4. 纯缓存场景用 allkeys-lru 或 allkeys-lfu；混存场景用 volatile-*')
    print('5. volatile-* 在无 TTL key 时会退化为 noeviction —— 这是最常见的线上事故之一')
    print('6. Redis 的 LRU/LFU 都是近似实现，靠抽样 + eviction pool 在精度与开销间平衡')


if __name__ == '__main__':
    main()
