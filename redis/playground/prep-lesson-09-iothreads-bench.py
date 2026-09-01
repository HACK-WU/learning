#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
实验 4：io-threads 实测
对比 io-threads = 1 / 4 / 8 在不同 value 大小与并发连接数下的吞吐。
注意：io-threads 只并行网络读写与协议解析，命令执行仍是单线程。
"""
import importlib.util
import time
import threading

spec = importlib.util.spec_from_file_location(
    "l09lib", "/mnt/d/projects/learning/redis/playground/prep-lesson-09-lib.py")
lib = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lib)

Redis, section, fmt_bytes = lib.Redis, lib.section, lib.fmt_bytes

section('实验 4：io-threads 实测（Redis 8.10.1, 20 核）')

CASES = [(7102, 1), (7103, 4), (7104, 8)]


def setup(port, vsize):
    c = Redis(port=port)
    c.cmd('FLUSHALL')
    # 预置 10000 个 key
    cmds = [('SET', 'k:%d' % i, 'v' * vsize) for i in range(10000)]
    for i in range(0, len(cmds), 1000):
        c.pipeline(cmds[i:i + 1000])
    c.close()


def bench(port, conns, n_total, vsize, use_pipe=False):
    per = n_total // conns
    barrier = threading.Barrier(conns)
    done = [0] * conns

    def worker(idx):
        c = Redis(port=port)
        barrier.wait()
        t0 = time.time()
        if use_pipe:
            for s in range(0, per, 50):
                c.pipeline([('GET', 'k:%d' % ((s + j) % 10000)) for j in range(50)])
        else:
            for i in range(per):
                c.cmd('GET', 'k:%d' % (i % 10000))
        done[idx] = time.time() - t0
        c.close()

    ths = [threading.Thread(target=worker, args=(i,)) for i in range(conns)]
    t0 = time.time()
    for t in ths:
        t.start()
    for t in ths:
        t.join()
    wall = time.time() - t0
    return n_total / wall


print('\n说明：本机为回环网络(lo)，网络开销小；')
print('      为使差异可见，同时测「小 value 单条」与「大 value 单条」。')
print('      value 越大，协议解析与网络读写的占比越高，io-threads 收益越明显。\n')

for vsize, vlabel in [(100, '100 B'), (5000, '5 KB')]:
    print('=' * 72)
    print('  value 大小 = %s' % vlabel)
    print('=' * 72)
    for port, t in CASES:
        setup(port, vsize)
    print('  %-12s %14s %14s %14s' % ('io-threads', '单连接', '8 连接', '32 连接'))
    base = {}
    for port, t in CASES:
        q1 = bench(port, 1, 40000, vsize)
        q8 = bench(port, 8, 160000, vsize)
        q32 = bench(port, 32, 320000, vsize)
        base[t] = q1
        print('  %-12d %14.0f %14.0f %14.0f' % (t, q1, q8, q32))
    gain1 = base[4] / base[1] if base[1] else 0
    gain2 = base[8] / base[1] if base[1] else 0
    print('  → 单连接场景：io-threads=4 相对 =1 提升 %.2fx；=8 提升 %.2fx'
          % (gain1, gain2))
    print()

# pipeline 场景
print('=' * 72)
print('  再用 pipeline 测（此时瓶颈在服务端处理，不在网络往返）')
print('=' * 72)
for port, t in CASES:
    setup(port, 100)
print('  %-12s %14s %14s' % ('io-threads', '8连接+pipe', '32连接+pipe'))
for port, t in CASES:
    q8 = bench(port, 8, 400000, 100, use_pipe=True)
    q32 = bench(port, 32, 800000, 100, use_pipe=True)
    print('  %-12d %14.0f %14.0f' % (t, q8, q32))

print('\n' + '=' * 72)
print('  实验 4 完成')
print('=' * 72)
