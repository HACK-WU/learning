#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
实验 1：性能诊断 —— 慢查询日志 / 大 key / 热 key / commandstats
在独立端口 7101 上构造含大 key 的数据集，验证四种诊断手段。
"""
import importlib.util
import time
import random
import string
import sys

spec = importlib.util.spec_from_file_location(
    "l09lib", "/mnt/d/projects/learning/redis/playground/prep-lesson-09-lib.py")
lib = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lib)

Redis, section, fmt_bytes = lib.Redis, lib.section, lib.fmt_bytes

r = Redis(port=7101)

section('实验 1：性能诊断四件套')

# ---------- 准备：清空并配置 ----------
print('\n【0. 初始化】')
r.cmd('FLUSHALL')
r.cmd('CONFIG', 'SET', 'slowlog-log-slower-than', '1000')  # 1ms 阈值，便于观察
r.cmd('CONFIG', 'SET', 'slowlog-max-len', '128')
r.cmd('SLOWLOG', 'RESET')
r.cmd('CONFIG', 'SET', 'latency-monitor-threshold', '10')
print('  slowlog-log-slower-than = 1000us (1ms)')
print('  latency-monitor-threshold = 10ms')
print('  数据集准备中 ...')

# ---------- 构造数据集 ----------
# a) 20000 个小 key（正常业务数据）
pipe = []
for i in range(20000):
    pipe.append(('SET', 'user:%d' % i, 'v' * 100))
r.pipeline(pipe)
print('  小 key: 20000 个 user:* (100B each)')

# b) 一个大 Hash（50 万字段）
big = []
for i in range(500000):
    big.append(('HSET', 'big:hash', 'f%d' % i, 'x' * 20))
for i in range(0, len(big), 5000):
    r.pipeline(big[i:i + 5000])
print('  大 Hash: big:hash (500000 字段)')

# c) 一个大 List（100 万元素）
for i in range(0, 1000000, 10000):
    args = ['RPUSH', 'big:list'] + ['e%d' % i for i in range(10000)]
    r.cmd(*args)
print('  大 List: big:list (1000000 元素)')

# d) 一个大 String（8MB 的 JSON-like）
big_str = 'x' * (8 * 1024 * 1024)
r.cmd('SET', 'big:string', big_str)
print('  大 String: big:string (8 MB)')

# e) 一个超大 ZSet
big = []
for i in range(200000):
    big.append(('ZADD', 'big:zset', i, 'm%d' % i))
for i in range(0, len(big), 5000):
    r.pipeline(big[i:i + 5000])
print('  大 ZSet: big:zset (200000 成员)')

dbsize = r.cmd('DBSIZE')
print('\n  DBSIZE = %d' % dbsize)

# ---------- 诊断手段 1：SLOWLOG ----------
print('\n' + '-' * 66)
print('【诊断 1】慢查询日志 SLOWLOG')

# 故意执行一些慢命令
print('  故意触发慢查询 ...')
t0 = time.time()
r.cmd('KEYS', '*')          # O(N)，全量扫描 —— 经典慢命令
t_keys = (time.time() - t0) * 1000
print('    KEYS *          耗时 %.2f ms' % t_keys)

t0 = time.time()
r.cmd('HGETALL', 'big:hash')   # 返回 50 万字段
t_hgetall = (time.time() - t0) * 1000
print('    HGETALL big:hash 耗时 %.2f ms' % t_hgetall)

t0 = time.time()
r.cmd('LRANGE', 'big:list', 0, -1)
t_lrange = (time.time() - t0) * 1000
print('    LRANGE big:list 0 -1 耗时 %.2f ms' % t_lrange)

t0 = time.time()
r.cmd('ZRANGE', 'big:zset', 0, -1, 'WITHSCORES')
t_zrange = (time.time() - t0) * 1000
print('    ZRANGE big:zset 0 -1 WITHSCORES 耗时 %.2f ms' % t_zrange)

t0 = time.time()
r.cmd('SMEMBERS', 'nosuchkey')  # 不存在的 key
print('    SMEMBERS 不存在key 耗时 %.2f ms' % ((time.time() - t0) * 1000))

time.sleep(0.2)
print('\n  --- SLOWLOG GET 5 ---')
sl = r.cmd('SLOWLOG', 'GET', '5')
print('  共 %d 条慢日志' % len(sl))
for i, e in enumerate(sl, 1):
    eid, ts, dur, command, caddr, cname = e[0], e[1], e[2], e[3], e[4], e[5]
    args = b' '.join(command).decode('utf-8', 'replace')
    if len(args) > 60:
        args = args[:60] + '...(截断)'
    print('   %2d) id=%-3d 耗时=%7d us (%6.2f ms)  命令=%s'
          % (i, int(eid), int(dur), int(dur) / 1000.0, args))

print('\n  SLOWLOG LEN =', r.cmd('SLOWLOG', 'LEN'))

print('\n  ⚠️ 关键对比：SLOWLOG 记录的耗时 vs 客户端感受到的耗时')
print('    %-34s %12s %14s' % ('命令', 'SLOWLOG(us)', '客户端实测(ms)'))
slow_map = {}
for e in sl:
    args = b' '.join(e[3]).decode('utf-8', 'replace')
    slow_map[args.split()[0]] = int(e[2])
cli_map = {
    'KEYS': t_keys, 'HGETALL': t_hgetall,
    'LRANGE': t_lrange, 'ZRANGE': t_zrange,
}
for c, cli_ms in cli_map.items():
    su = slow_map.get(c, 0)
    print('    %-34s %12d %14.2f' % (c, su, cli_ms))
print('    → SLOWLOG 只记「命令执行」时间，不含网络传输与客户端解析；')
print('      大返回值命令的客户端耗时可能是 SLOWLOG 的数十倍。')

# ---------- 诊断手段 2：大 key ----------
print('\n' + '-' * 66)
print('【诊断 2】大 key 定位')

print('\n  (a) MEMORY USAGE —— 精确测量单个 key')
for k in ['big:hash', 'big:list', 'big:zset', 'big:string', 'user:1']:
    u = r.cmd('MEMORY', 'USAGE', k)
    t = r.cmd('TYPE', k)
    if isinstance(t, bytes):
        t = t.decode()
    print('    %-12s type=%-8s usage=%s' % (k, t, fmt_bytes(int(u))))

print('\n  (b) 各类型元素个数（复杂度维度，不是大小维度）')
print('    big:hash   HLEN   =', r.cmd('HLEN', 'big:hash'))
print('    big:list   LLEN   =', r.cmd('LLEN', 'big:list'))
print('    big:zset   ZCARD  =', r.cmd('ZCARD', 'big:zset'))
print('    big:string STRLEN =', r.cmd('STRLEN', 'big:string'))

print('\n  (c) 用 SCAN + MEMORY USAGE 自己扫（生产可用做法）')
t0 = time.time()
cur = b'0'
found = []
scanned = 0
while True:
    cur, keys = r.cmd('SCAN', cur, 'COUNT', '500')
    scanned += len(keys)
    for k in keys:
        kd = k.decode()
        # 只对可疑前缀测，避免全量测太慢
        if kd.startswith('big:') or kd.startswith('user:'):
            u = int(r.cmd('MEMORY', 'USAGE', k))
            found.append((u, kd))
    if cur == b'0':
        break
found.sort(reverse=True)
dt = time.time() - t0
print('    扫描 %d 个 key 耗时 %.2f s' % (scanned, dt))
print('    Top 5 大 key:')
for u, k in found[:5]:
    print('      %-14s %s' % (k, fmt_bytes(u)))

# ---------- 诊断手段 3：热 key ----------
print('\n' + '-' * 66)
print('【诊断 3】热 key 定位')

# 制造明显的热点：对少量 key 超高并发访问
print('  制造热点：对 hot:1 ~ hot:10 各访问 20000 次，其他 key 各访问几次 ...')
for i in range(1, 11):
    r.cmd('SET', 'hot:%d' % i, 'x' * 200)
pipe = []
for i in range(1, 11):
    for _ in range(20000):
        pipe.append(('GET', 'hot:%d' % i))
for i in range(0, len(pipe), 5000):
    r.pipeline(pipe[i:i + 5000])
print('  热点访问完成')

print('\n  (a) OBJECT FREQ —— 需要 maxmemory-policy 为 LFU 才有效')
cur_policy = r.cmd('CONFIG', 'GET', 'maxmemory-policy')[1].decode()
print('    当前策略 = %s' % cur_policy)
if 'lfu' in cur_policy:
    for i in range(1, 6):
        f = r.cmd('OBJECT', 'FREQ', 'hot:%d' % i)
        print('      hot:%d freq = %s' % (i, f))
else:
    try:
        f = r.cmd('OBJECT', 'FREQ', 'hot:1')
        print('    在非 LFU 策略下 OBJECT FREQ = %s' % f)
    except lib.RedisError as e:
        print('    在非 LFU 策略（%s）下调用 OBJECT FREQ，Redis 直接报错：' % cur_policy)
        print('      ERR: %s' % e)
        print('    → 这就是「OBJECT FREQ 有前提」的铁证：')
        print('      24 bit LRU 字段在 LFU 策略下才被解释为频率计数器。')
    r.cmd('CONFIG', 'SET', 'maxmemory-policy', 'allkeys-lfu')
    print('    切换到 allkeys-lfu 后重新访问 ...')
    pipe = []
    for i in range(1, 11):
        for _ in range(20000):
            pipe.append(('GET', 'hot:%d' % i))
    for i in range(0, len(pipe), 5000):
        r.pipeline(pipe[i:i + 5000])
    print('    hot key 的 LFU 计数：')
    for i in range(1, 6):
        print('      hot:%d freq = %s' % (i, r.cmd('OBJECT', 'FREQ', 'hot:%d' % i)))
    print('    冷 key 的 LFU 计数：')
    for k in ['user:1', 'user:2', 'user:3']:
        print('      %-8s freq = %s' % (k, r.cmd('OBJECT', 'FREQ', k)))
    r.cmd('CONFIG', 'SET', 'maxmemory-policy', cur_policy)

print('\n  (b) OBJECT IDLETIME —— 空闲秒数（LRU 视角）')
r.cmd('CONFIG', 'GET', 'maxmemory-policy')
print('    hot:1  idletime = %s s' % r.cmd('OBJECT', 'IDLETIME', 'hot:1'))
print('    user:1 idletime = %s s' % r.cmd('OBJECT', 'IDLETIME', 'user:1'))

# ---------- 诊断手段 4：commandstats ----------
print('\n' + '-' * 66)
print('【诊断 4】INFO commandstats —— 命令维度统计')

raw = r.cmd('INFO', 'commandstats')
if isinstance(raw, bytes):
    raw = raw.decode('utf-8', 'replace')
lines = [l for l in raw.splitlines() if l.startswith('cmdstat_')]
stats = []
for l in lines:
    name, rest = l.split(':', 1)
    d = {}
    for kv in rest.split(','):
        k, v = kv.split('=')
        d[k] = float(v)
    stats.append((name.replace('cmdstat_', ''), d))
stats.sort(key=lambda x: -x[1].get('usec', 0))

print('  按总耗时(usec) Top 10:')
print('    %-22s %10s %12s %12s' % ('命令', '调用次数', '总耗时usec', '平均usec'))
for name, d in stats[:10]:
    print('    %-22s %10d %12.0f %12.2f'
          % (name, int(d.get('calls', 0)), d.get('usec', 0), d.get('usec_per_call', 0)))

print('\n  按调用次数 Top 5:')
for name, d in sorted(stats, key=lambda x: -x[1].get('calls', 0))[:5]:
    print('    %-22s calls=%d  usec_per_call=%.2f'
          % (name, int(d.get('calls', 0)), d.get('usec_per_call', 0)))

# ---------- 关键指标 ----------
print('\n' + '-' * 66)
print('【诊断 5】INFO 关键健康指标')

for sec_name, fields in [
    ('stats', ['instantaneous_ops_per_sec', 'keyspace_hits', 'keyspace_misses',
               'expired_keys', 'evicted_keys', 'rejected_connections',
               'latest_fork_usec', 'total_commands_processed']),
    ('memory', ['used_memory_human', 'used_memory_peak_human',
                'mem_fragmentation_ratio', 'maxmemory_policy']),
    ('clients', ['connected_clients', 'blocked_clients',
                 'client_recent_max_input_buffer']),
]:
    raw = r.cmd('INFO', sec_name)
    if isinstance(raw, bytes):
        raw = raw.decode('utf-8', 'replace')
    d = {}
    for l in raw.splitlines():
        if ':' in l and not l.startswith('#'):
            k, v = l.split(':', 1)
            d[k] = v
    print('\n  [%s]' % sec_name)
    for f in fields:
        if f in d:
            print('    %-32s = %s' % (f, d[f]))

hits = int(d.get('keyspace_hits', 0)) if sec_name == 'stats' else 0

# 命中率
raw = r.cmd('INFO', 'stats')
if isinstance(raw, bytes):
    raw = raw.decode('utf-8', 'replace')
sd = {}
for l in raw.splitlines():
    if ':' in l and not l.startswith('#'):
        k, v = l.split(':', 1)
        sd[k] = v
h = int(sd.get('keyspace_hits', 0))
m = int(sd.get('keyspace_misses', 0))
if h + m > 0:
    print('\n  缓存命中率 = %d / (%d + %d) = %.2f%%' % (h, h, m, h * 100.0 / (h + m)))

# ---------- LATENCY ----------
print('\n' + '-' * 66)
print('【诊断 6】LATENCY 监控')

lat = r.cmd('LATENCY', 'LATEST')
print('  LATENCY LATEST:', lat if not lat else '有事件')

print('\n  执行一次大 key 删除，看是否产生延迟事件 ...')
r.cmd('CONFIG', 'SET', 'latency-monitor-threshold', '5')
t0 = time.time()
r.cmd('DEL', 'big:list')     # 释放 100 万元素的 list，通常较慢
dt = (time.time() - t0) * 1000
print('    DEL big:list 耗时 %.2f ms' % dt)
time.sleep(0.3)
lat = r.cmd('LATENCY', 'LATEST')
if lat:
    for e in lat:
        ev = e[0].decode() if isinstance(e[0], bytes) else str(e[0])
        print('    事件: %-20s 峰值延迟=%s ms  发生时间=%s'
              % (ev, e[2], time.strftime('%H:%M:%S', time.localtime(int(e[1])))))
else:
    print('    未捕获到延迟事件（%d ms 低于阈值或 Redis 8 释放较快）' % dt)

print('\n  LATENCY DOCTOR:')
doc = r.cmd('LATENCY', 'DOCTOR')
if isinstance(doc, bytes):
    doc = doc.decode('utf-8', 'replace')
for line in doc.splitlines():
    if line.strip():
        print('    ' + line)

print('\n' + '=' * 66)
print('  实验 1 完成')
print('=' * 66)
r.close()
