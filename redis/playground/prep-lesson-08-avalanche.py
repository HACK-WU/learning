#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8 知识点 1（雪崩部分）实测：大批 key 同时过期的后果 + 缓存层整体失效。

四组实验：
  A. 统一 TTL     —— 所有 key 同一时刻过期，观察 DB 压力尖峰
  B. 随机 TTL     —— 基础 TTL + 随机抖动，观察压力是否被摊平
  C. Redis 宕机   —— 缓存层整体不可用（雪崩的第二种成因）
  D. 对照组       —— key 永不过期时的 DB 压力基线

统计口径说明（重要）：
  按"观察窗起点"计算相对秒，并对观察窗内每一秒全量填充（没查询的秒补 0）。
  若只统计"有查询的秒"，尖峰会被均值稀释，无法体现雪崩特征。
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

PORT = 7101
N_KEYS = 3000           # 缓存 key 数量
BASE_TTL = 15           # 基础 TTL（秒）
JITTER = 60             # 随机抖动上限（秒）
READ_RPS = 200          # 持续读 QPS
DURATION = 26           # 观察时长（秒）
DB_LATENCY = 0.001      # DB 单次查询 1ms
NTHREADS = 8


def banner(t):
    print('\n' + '=' * 68)
    print(t)
    print('=' * 68)


class DB(FakeDB):
    """FakeDB + 按"观察窗相对秒"统计查询次数（缺失秒补 0）。"""

    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        self.t0 = None
        self.per_sec = {}
        self.plock = threading.Lock()

    def start(self):
        with self.plock:
            self.t0 = time.time()
            self.per_sec = {}

    def _bump(self):
        with self.plock:
            if self.t0 is None:
                return
            s = int(time.time() - self.t0)
            self.per_sec[s] = self.per_sec.get(s, 0) + 1

    def get(self, k):
        self._bump()
        return super().get(k)

    def set(self, k, v):
        self._bump()
        return super().set(k, v)

    def reset(self):
        super().reset_stats()
        with self.plock:
            self.t0 = time.time()
            self.per_sec = {}

    def series(self, n=DURATION):
        """返回长度 n 的完整时间序列，缺失补 0。"""
        return [self.per_sec.get(i, 0) for i in range(n)]


def report(db, label, note=''):
    s = db.series(DURATION)
    total = sum(s)
    peak = max(s)
    peak_at = s.index(peak)
    avg = total / float(DURATION)
    print('观察窗          : %d 秒（%d 读线程，目标 %d QPS）' % (DURATION, NTHREADS, READ_RPS))
    print('DB 查询总次数   : %d' % total)
    print('DB 峰值         : %d 次/秒（发生在第 %d 秒）' % (peak, peak_at))
    print('DB 均值         : %.1f 次/秒' % avg)
    print('峰值/均值       : %.1f 倍' % (peak / avg if avg else 0))
    print('DB 瞬时最大并发 : %d' % db.max_concurrent)
    if note:
        print('说明            : %s' % note)
    print('\n每秒 DB 查询分布（相对秒 : 次数 : 柱状图，无查询的秒显示为空）:')
    mx = max(1, peak)
    for i, c in enumerate(s):
        bar = '#' * int(c * 50.0 / mx)
        mark = ' <== 过期时刻' if (i == peak_at and peak > 0) else ''
        print('  %3ds | %5d | %-50s%s' % (i, c, bar, mark))
    return total, peak, avg


def simulate(ttl_fn, label, note=''):
    banner(label)
    r = Redis(port=PORT)
    r.flushdb()
    db = DB(data={i: 'v%d' % i for i in range(N_KEYS)}, latency=DB_LATENCY)
    db.reset()

    for i in range(N_KEYS):
        r.set('item:%d' % i, 'v%d' % i, ex=ttl_fn())
    sample = [r.cmd('TTL', 'item:%d' % k) for k in range(0, N_KEYS, 500)]
    print('预热 %d 个 key 完成，TTL 抽样: %s' % (N_KEYS, sample))

    stop = threading.Event()
    db.start()

    def reader():
        rr = Redis(port=PORT)
        interval = 1.0 / (READ_RPS / NTHREADS)
        while not stop.is_set():
            t = time.time()
            k = random.randrange(N_KEYS)
            try:
                v = rr.get('item:%d' % k)
            except Exception:
                v = None
            if v is None:
                val = db.get(k)
                try:
                    rr.set('item:%d' % k, 'v%d' % k, ex=ttl_fn())
                except Exception:
                    pass
            dt = time.time() - t
            if dt < interval:
                time.sleep(interval - dt)
        rr.close()

    ts = [threading.Thread(target=reader) for _ in range(NTHREADS)]
    for t in ts:
        t.start()
    time.sleep(DURATION)
    stop.set()
    for t in ts:
        t.join()

    res = report(db, label, note)
    r.close()
    return res


def test_redis_down():
    """C. 缓存层整体不可用 —— 雪崩的第二种成因。"""
    banner('C. Redis 宕机 —— 缓存层整体失效，全部流量涌向 DB')
    r = Redis(port=PORT)
    r.flushdb()
    db = DB(data={i: 'v%d' % i for i in range(N_KEYS)}, latency=DB_LATENCY)
    db.reset()
    r.close()

    # 关闭 Redis 实例，模拟缓存层不可用
    rc = os.system('redis-cli -p %d shutdown nosave 2>/dev/null' % PORT)
    time.sleep(0.5)
    print('已执行: redis-cli -p %d shutdown nosave (rc=%d)' % (PORT, rc))

    alive = False
    try:
        rr = Redis(port=PORT, timeout=1)
        rr.cmd('PING')
        alive = True
        rr.close()
    except Exception as e:
        print('确认 Redis 不可用: %s' % type(e).__name__)
    if alive:
        print('警告：Redis 仍可用，本组实验无效')
        return 0, 0, 0

    stop = threading.Event()
    db.start()
    down_errors = [0]
    elock = threading.Lock()

    def reader():
        interval = 1.0 / (READ_RPS / NTHREADS)
        while not stop.is_set():
            t = time.time()
            try:
                rr = Redis(port=PORT, timeout=0.5)
                rr.get('item:%d' % random.randrange(N_KEYS))
                rr.close()
            except Exception:
                with elock:
                    down_errors[0] += 1
                db.get(random.randrange(N_KEYS))   # 降级：直接查 DB
            dt = time.time() - t
            if dt < interval:
                time.sleep(interval - dt)

    ts = [threading.Thread(target=reader) for _ in range(NTHREADS)]
    for t in ts:
        t.start()
    time.sleep(min(DURATION, 12))
    stop.set()
    for t in ts:
        t.join()

    print('Redis 连接失败次数: %d（每次失败都降级查 DB）' % down_errors[0])
    res = report(db, 'C', note='观察窗缩短为 12 秒；Redis 全程不可用')
    return res


def main():
    print('实验参数：%d 个 key，基础 TTL %ds，读流量 %d QPS，观察窗 %ds\n'
          % (N_KEYS, BASE_TTL, READ_RPS, DURATION))
    print('注意：本脚本会临时关闭 7101 实例（组 C），结束后需重新启动。')

    a_total, a_peak, a_avg = simulate(
        lambda: BASE_TTL,
        'A. 统一 TTL —— 所有 key 都在第 %d 秒同时过期' % BASE_TTL,
        note='前 %d 秒 DB 查询为 0，因为缓存全部命中' % (BASE_TTL - 1))

    time.sleep(1)

    b_total, b_peak, b_avg = simulate(
        lambda: BASE_TTL + random.randint(0, JITTER),
        'B. 随机 TTL —— 基础 %ds + 随机 0~%ds 抖动' % (BASE_TTL, JITTER),
        note='过期时间被打散，同一秒只有少量 key 需要重建')

    c_total, c_peak, c_avg = test_redis_down()

    # 重启实例供后续实验使用
    print('\n正在重启 7101 实例...')
    os.system('redis-server --port %d --loadmodule /usr/lib/redis/modules/redisbloom.so '
              '--save "" --appendonly no --dir /tmp/redis-l08 --dbfilename l08.rdb '
              '--daemonize yes --logfile /tmp/redis-l08/%d.log' % (PORT, PORT))
    for _ in range(50):
        time.sleep(0.1)
        try:
            rr = Redis(port=PORT, timeout=1)
            rr.cmd('PING')
            rr.close()
            print('7101 已恢复')
            break
        except Exception:
            pass

    banner('汇总：三种场景下的 DB 压力')
    print('%-28s %-12s %-14s %-12s' % ('场景', 'DB 总查询', 'DB 峰值/秒', '峰值/均值'))
    print('-' * 68)
    print('%-28s %-12d %-14d %-12.1f' % ('A 统一 TTL（同时过期）', a_total, a_peak,
                                        a_peak / a_avg if a_avg else 0))
    print('%-28s %-12d %-14d %-12.1f' % ('B 随机 TTL（过期打散）', b_total, b_peak,
                                        b_peak / b_avg if b_avg else 0))
    print('%-28s %-12d %-14d %-12.1f' % ('C Redis 宕机（缓存层失效）', c_total, c_peak,
                                        c_peak / c_avg if c_avg else 0))
    if b_peak:
        print('\nB 相对 A：DB 峰值降低 %.1f 倍，总查询降低 %.1f 倍'
              % (a_peak / float(b_peak), a_total / float(b_total) if b_total else 0))


if __name__ == '__main__':
    main()
