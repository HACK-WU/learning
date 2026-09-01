#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
实验 3：性能与运维基线
(a) pipeline 对吞吐的影响（网络往返是主要成本）
(b) 大 key 删除的阻塞代价（对比大 key vs 拆分小 key）
(c) maxmemory 保护：不设限会发生什么
(d) io-threads 实测
(e) 连接数 / 客户端缓冲区
"""
import importlib.util
import time
import threading
import statistics

spec = importlib.util.spec_from_file_location(
    "l09lib", "/mnt/d/projects/learning/redis/playground/prep-lesson-09-lib.py")
lib = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lib)

Redis, section, fmt_bytes = lib.Redis, lib.section, lib.fmt_bytes

PORT = 7101
r = Redis(port=PORT)

section('实验 3：性能与运维基线')

# ---------- 1. pipeline 的价值 ----------
print('\n【1. pipeline：网络往返才是主要成本】')
r.cmd('FLUSHALL')
r.cmd('CONFIG', 'SET', 'slowlog-log-slower-than', '100000')

N = 20000
print('  写入 %d 个 key，分别用三种方式：' % N)

# (a) 逐条（每条等一次往返）
t0 = time.time()
for i in range(N):
    r.cmd('SET', 'p:seq:%d' % i, 'x' * 50)
dt_seq = time.time() - t0
print('    (a) 逐条发送           : %7.3f s  %10.0f ops/s' % (dt_seq, N / dt_seq))

# (b) pipeline 分批
r.cmd('FLUSHALL')
t0 = time.time()
BATCH = 500
for start in range(0, N, BATCH):
    cmds = [('SET', 'p:pipe:%d' % i, 'x' * 50) for i in range(start, min(start + BATCH, N))]
    r.pipeline(cmds)
dt_pipe = time.time() - t0
print('    (b) pipeline(批%d)      : %7.3f s  %10.0f ops/s' % (BATCH, dt_pipe, N / dt_pipe))

# (c) 单次大 pipeline
r.cmd('FLUSHALL')
t0 = time.time()
cmds = [('SET', 'p:big:%d' % i, 'x' * 50) for i in range(N)]
r.pipeline(cmds)
dt_big = time.time() - t0
print('    (c) 单次超大pipeline(N) : %7.3f s  %10.0f ops/s' % (dt_big, N / dt_big))

print('\n  结论：pipeline 比逐条快 %.1f 倍，比超大 pipeline 快 %.2f 倍'
      % (dt_seq / dt_pipe, dt_big / dt_pipe if dt_big > 0 else 0))
print('  ⚠️ 但 pipeline 不是越大越好：一批太大 Redis 要分配大缓冲区，')
print('     且会让这条连接堵住其他请求。生产常用 100~1000 一批。')

# ---------- 2. 大 key 删除的阻塞代价 ----------
print('\n' + '-' * 66)
print('【2. 大 key 删除：为什么「删数据」也会引发故障】')

print('\n  构造两个「总量相同但粒度不同」的对象：')
print('    A) 1 个大 Hash：100 万字段')
print('    B) 1000 个小 Hash：每个 1000 字段（总量同样 100 万字段）')

# A: 一个大 hash
r.cmd('FLUSHALL')
cmds = [('HSET', 'huge:hash', 'f%d' % i, 'v' * 20) for i in range(1000000)]
for i in range(0, len(cmds), 5000):
    r.pipeline(cmds[i:i + 5000])
print('    A 构造完成，MEMORY USAGE =', fmt_bytes(int(r.cmd('MEMORY', 'USAGE', 'huge:hash'))))

# 测量删除耗时：用「另一条连接」在删除期间探测延迟
probe = Redis(port=PORT)
def measure_delete(key_or_keys):
    """删除期间用另一条连接反复 PING，测量被阻塞多久"""
    stop = threading.Event()
    lat = []
    def prober():
        while not stop.is_set():
            t = time.time()
            try:
                probe.cmd('PING')
            except Exception:
                pass
            lat.append((time.time() - t) * 1000)
    th = threading.Thread(target=prober, daemon=True)
    th.start()
    time.sleep(0.1)

    t0 = time.time()
    if isinstance(key_or_keys, list):
        for k in key_or_keys:
            r.cmd('DEL', k)
    else:
        r.cmd('DEL', key_or_keys)
    dt = (time.time() - t0) * 1000
    stop.set()
    th.join(timeout=2)
    return dt, (max(lat) if lat else 0), (statistics.mean(lat) if lat else 0)

dt_a, mx_a, av_a = measure_delete('huge:hash')
print('\n    A) DEL huge:hash（1 个 100 万字段的 Hash）')
print('       删除耗时 %.2f ms' % dt_a)
print('       删除期间其他客户端 PING 最大延迟 %.2f ms（平时约 0.05 ms）' % mx_a)

# B: 1000 个小 hash
r.cmd('FLUSHALL')
cmds = []
for h in range(1000):
    for i in range(1000):
        cmds.append(('HSET', 'small:hash:%d' % h, 'f%d' % i, 'v' * 20))
for i in range(0, len(cmds), 5000):
    r.pipeline(cmds[i:i + 5000])
keys_b = ['small:hash:%d' % h for h in range(1000)]
tot_b = sum(int(r.cmd('MEMORY', 'USAGE', k)) for k in keys_b[:100]) * 10
print('    B 构造完成，估算总内存 ≈', fmt_bytes(tot_b))

dt_b, mx_b, av_b = measure_delete(keys_b)
print('\n    B) DEL 1000 个小 Hash（每个 1000 字段）')
print('       删除总耗时 %.2f ms（1000 次 DEL）' % dt_b)
print('       删除期间其他客户端 PING 最大延迟 %.2f ms' % mx_b)

print('\n    对比：单次删除阻塞 %.2f ms vs %.2f ms' % (mx_a, mx_b))
if mx_a > mx_b * 2:
    print('    → 大 key 删除造成的服务停顿是小 key 的 %.1f 倍' % (mx_a / max(mx_b, 0.01)))
    print('      这就是「拆分大 key」的核心理由：不是省内存，是避免长停顿。')

# ---------- 3. 异步删除 UNLINK ----------
print('\n' + '-' * 66)
print('【3. UNLINK：把释放工作甩给后台线程】')

r.cmd('FLUSHALL')
cmds = [('HSET', 'huge2:hash', 'f%d' % i, 'v' * 20) for i in range(1000000)]
for i in range(0, len(cmds), 5000):
    r.pipeline(cmds[i:i + 5000])

stop = threading.Event()
lat = []
def prober():
    while not stop.is_set():
        t = time.time()
        try:
            probe.cmd('PING')
        except Exception:
            pass
        lat.append((time.time() - t) * 1000)
th = threading.Thread(target=prober, daemon=True)
th.start()
time.sleep(0.1)
t0 = time.time()
r.cmd('UNLINK', 'huge2:hash')
dt_u = (time.time() - t0) * 1000
stop.set()
th.join(timeout=2)
mx_u = max(lat) if lat else 0

print('  UNLINK huge2:hash（同样 100 万字段）')
print('    调用返回耗时 %.2f ms  （对比 DEL 的 %.2f ms）' % (dt_u, dt_a))
print('    期间其他客户端 PING 最大延迟 %.2f ms（DEL 时为 %.2f ms）' % (mx_u, mx_a))
if mx_u < mx_a:
    print('    → UNLINK 把阻塞从 %.2f ms 降到 %.2f ms，降低 %.0f%%'
          % (mx_a, mx_u, (1 - mx_u / mx_a) * 100))
print('  原理：UNLINK 只把 key 从 keyspace 摘除（O(1)），')
print('        真正的内存释放交给后台线程 lazyfree 慢慢做。')

r.cmd('FLUSHALL')

# ---------- 4. io-threads 实测 ----------
print('\n' + '-' * 66)
print('【4. io-threads：多核时代的选择】')

print('  当前 io-threads =', r.cmd('CONFIG', 'GET', 'io-threads')[1])
print('  本机 CPU 核数 = 20')
print('  注意：io-threads 只并行「网络读写与解析」，命令执行仍是单线程。')

def bench_get(n=100000, conns=1):
    """用 conns 条连接并发 GET，返回 QPS"""
    r.cmd('SET', 'bench:k', 'y' * 100)
    per = n // conns
    results = []
    barrier = threading.Barrier(conns)
    def worker():
        c = Redis(port=PORT)
        barrier.wait()
        t0 = time.time()
        for _ in range(per):
            c.cmd('GET', 'bench:k')
        results.append(time.time() - t0)
        c.close()
    ths = [threading.Thread(target=worker) for _ in range(conns)]
    t0 = time.time()
    for t in ths:
        t.start()
    for t in ths:
        t.join()
    wall = time.time() - t0
    return n / wall

for threads in [1, 4, 8]:
    r.cmd('CONFIG', 'SET', 'io-threads', str(threads))
    qps1 = bench_get(60000, conns=1)
    qps8 = bench_get(120000, conns=8)
    print('    io-threads=%-2d : 单连接 %8.0f ops/s    8 并发连接 %8.0f ops/s'
          % (threads, qps1, qps8))
r.cmd('CONFIG', 'SET', 'io-threads', '1')

print('\n  ⚠️ 实测说明：io-threads 的收益取决于「网络读写占总耗时的比例」。')
print('     本机是本机回环(lo)，网络开销极小，所以收益不明显；')
print('     真实跨网络、多连接、大 value 场景收益才显著。')

# ---------- 5. 不设 maxmemory 的后果 ----------
print('\n' + '-' * 66)
print('【5. maxmemory：不设限会发生什么】')

print('  当前 maxmemory =', r.cmd('CONFIG', 'GET', 'maxmemory')[1], '(0 = 不限制)')
print('  maxmemory-policy =', r.cmd('CONFIG', 'GET', 'maxmemory-policy')[1])
print('\n  不限制内存意味着 Redis 会一直吃内存，直到：')
print('    - 触发系统 OOM Killer 被杀掉（最惨，进程直接消失）')
print('    - 或内存耗尽导致 fork 失败（RDB/AOF 无法持久化）')
print('\n  演示：设一个小 maxmemory，看触发淘汰时的行为')

r.cmd('FLUSHALL')
r.cmd('CONFIG', 'SET', 'maxmemory', '20mb')
r.cmd('CONFIG', 'SET', 'maxmemory-policy', 'allkeys-lru')
print('    已设 maxmemory=20mb, policy=allkeys-lru')

ok = fail = 0
i = 0
while i < 300000:
    cmds = [('SET', 'm:k:%d' % (i + j), 'z' * 200) for j in range(1000)]
    res = r.pipeline(cmds)
    ok += sum(1 for x in res if not isinstance(x, lib.RedisError))
    fail += sum(1 for x in res if isinstance(x, lib.RedisError))
    i += 1000

info = r.cmd('INFO', 'stats')
if isinstance(info, bytes):
    info = info.decode('utf-8', 'replace')
evicted = used = 0
for l in info.splitlines():
    if l.startswith('evicted_keys:'):
        evicted = int(l.split(':')[1])
minfo = r.cmd('INFO', 'memory')
if isinstance(minfo, bytes):
    minfo = minfo.decode('utf-8', 'replace')
for l in minfo.splitlines():
    if l.startswith('used_memory:'):
        used = int(l.split(':')[1])

print('    写入 300000 个 key（每个 200B，理论约 60MB）')
print('    实际 DBSIZE =', r.cmd('DBSIZE'))
print('    used_memory =', fmt_bytes(used), '(被 maxmemory 限制在 20MB 附近)')
print('    evicted_keys =', evicted, '（被淘汰的 key 数）')
print('    → 有 maxmemory 保护：内存可控，靠淘汰换取可用性')
print('      没有的话：内存无限增长直到 OOM')

r.cmd('CONFIG', 'SET', 'maxmemory', '0')
r.cmd('CONFIG', 'SET', 'maxmemory-policy', 'noeviction')
r.cmd('FLUSHALL')

# ---------- 6. 客户端输出缓冲区 ----------
print('\n' + '-' * 66)
print('【6. 客户端缓冲区：一个容易被忽视的 OOM 源】')

print('  配置：')
for cfg in ['client-output-buffer-limit']:
    v = r.cmd('CONFIG', 'GET', cfg)
    print('    %s = %s' % (cfg, v[1]))

print('\n  含义：normal 客户端默认不限制；pubsub / replica 有硬限制。')
print('  风险场景：订阅者消费慢 → 输出缓冲区堆积 → Redis 内存暴涨')
print('  这正是为什么「Redis 内存突然涨了但 key 没变多」的常见原因之一。')

r.cmd('CONFIG', 'SET', 'slowlog-log-slower-than', '10000')
r.cmd('FLUSHALL')

print('\n' + '=' * 66)
print('  实验 3 完成')
print('=' * 66)
r.close()
