#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
实验 5：选型决策的实测依据
(1) 同一批数据，String 逐个存 vs Hash 分桶存 —— 内存效率对比
(2) 精确结构(Set) vs 概率结构(Bloom) —— 内存对比
(3) 什么时候 Redis 不是答案：按条件筛选是 O(N) 全量传输
"""
import importlib.util
import time
import json

spec = importlib.util.spec_from_file_location(
    "l09lib", "/mnt/d/projects/learning/redis/playground/prep-lesson-09-lib.py")
lib = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lib)

Redis, section, fmt_bytes = lib.Redis, lib.section, lib.fmt_bytes

PORT = 7105
r = Redis(port=PORT)


def mem():
    info = r.cmd('INFO', 'memory')
    if isinstance(info, bytes):
        info = info.decode('utf-8', 'replace')
    d = {}
    for l in info.splitlines():
        if ':' in l and not l.startswith('#'):
            k, v = l.split(':', 1)
            d[k] = v
    return int(d.get('used_memory', 0)), d.get('mem_fragmentation_ratio', '')


section('实验 5：选型决策的实测依据')

# ---------- 1. String 逐个 vs Hash 分桶 ----------
print('\n【1. 同一个业务对象，两种存法的内存开销】')
print('  数据：100 万个用户对象，每个 value 约 100 字节\n')

N = 1000000
VAL = 'x' * 100

# A: 100 万个独立 String
r.cmd('FLUSHALL')
base, _ = mem()
t0 = time.time()
for i in range(0, N, 2000):
    cmds = [('SET', 'user:%d' % (i + j), VAL) for j in range(2000)]
    r.pipeline(cmds)
dt_a = time.time() - t0
used_a, frag_a = mem()
print('  (A) 100 万个独立 String key')
print('      DBSIZE      = %d' % r.cmd('DBSIZE'))
print('      写入耗时    = %.2f s' % dt_a)
print('      数据集内存  = %s' % fmt_bytes(used_a - base))
print('      碎片率      = %s' % frag_a)

# B: 分桶 Hash（每桶 1000 字段）
r.cmd('FLUSHALL')
base, _ = mem()
t0 = time.time()
for b in range(0, N // 1000):
    cmds = [('HSET', 'bucket:%d' % b, str(b * 1000 + j), VAL) for j in range(1000)]
    r.pipeline(cmds)
dt_b = time.time() - t0
used_b, frag_b = mem()
print('\n  (B) 1000 个 Hash 桶，每桶 1000 字段')
print('      DBSIZE      = %d' % r.cmd('DBSIZE'))
print('      写入耗时    = %.2f s' % dt_b)
print('      数据集内存  = %s' % fmt_bytes(used_b - base))
print('      碎片率      = %s' % frag_b)

save_a = used_a - base
save_b = used_b - base
print('\n  内存对比：String %s vs Hash 分桶 %s' % (fmt_bytes(save_a), fmt_bytes(save_b)))
if save_b < save_a:
    print('  → Hash 分桶省了 %s（%.1f%%）'
          % (fmt_bytes(save_a - save_b), (1 - save_b / save_a) * 100))
print('\n  为什么：每个独立 key 都要带 robj 头、dictEntry、SDS 等固定开销；')
print('          Hash 用 listpack 编码时，1000 个字段共享一个 key 的开销。')
print('  但代价：分桶后无法对单个 field 设 TTL，也无法单独淘汰某个用户。')

print('\n  --- 关键：listpack 编码有前提 ---')
for cfg in ['hash-max-listpack-entries', 'hash-max-listpack-value']:
    v = r.cmd('CONFIG', 'GET', cfg)
    print('      %-32s = %s' % (cfg, v[1]))
r.cmd('HSET', 'probe:small', 'f1', 'v1')
print('      probe:small (1 字段) 编码 =', r.cmd('OBJECT', 'ENCODING', 'probe:small'))
print('      bucket:0 (1000 字段) 编码 =', r.cmd('OBJECT', 'ENCODING', 'bucket:0'))
print('      ↑ 超过 %s 个字段就会从 listpack 退化为 hashtable，省内存效果消失'
      % r.cmd('CONFIG', 'GET', 'hash-max-listpack-entries')[1].decode())

# ---------- 2. 精确 vs 概率 ----------
print('\n' + '-' * 66)
print('【2. 精确结构 vs 概率结构：10 万个 id 的内存代价】')

r.cmd('FLUSHALL')
t0 = time.time()
for i in range(0, 100000, 1000):
    cmds = [('SADD', 'idset', 'id:%d' % (i + j)) for j in range(1000)]
    r.pipeline(cmds)
sz_set = int(r.cmd('MEMORY', 'USAGE', 'idset'))
print('  (A) Set（精确，无误差）')
print('      SCARD         = %d' % r.cmd('SCARD', 'idset'))
print('      MEMORY USAGE  = %s' % fmt_bytes(sz_set))

r.cmd('FLUSHALL')
try:
    r.cmd('BF.RESERVE', 'idfilter', '0.001', '100000')
except lib.RedisError:
    pass
for i in range(0, 100000, 1000):
    cmds = [('BF.ADD', 'idfilter', 'id:%d' % (i + j)) for j in range(1000)]
    r.pipeline(cmds)
sz_bf = int(r.cmd('MEMORY', 'USAGE', 'idfilter'))
print('\n  (B) 布隆过滤器（概率，声明误判率 0.1%）')
print('      MEMORY USAGE  = %s' % fmt_bytes(sz_bf))

print('\n  精确 vs 概率：%s vs %s' % (fmt_bytes(sz_set), fmt_bytes(sz_bf)))
print('  → 概率结构省了 %.1f 倍内存' % (sz_set / sz_bf))
print('     代价：存在误判（说"存在"可能不存在），且不支持删除。')

# 实测误判率
fp = 0
tests = 100000
for i in range(0, tests, 1000):
    cmds = [('BF.EXISTS', 'idfilter', 'nope:%d' % (i + j)) for j in range(1000)]
    res = r.pipeline(cmds)
    fp += sum(1 for x in res if x == 1)
print('     实测误判率：%d / %d = %.4f%%（声明 0.1%%）' % (fp, tests, fp * 100.0 / tests))

# ---------- 3. 什么时候 Redis 不是答案 ----------
print('\n' + '-' * 66)
print('【3. 什么时候「不该用 Redis」：按条件筛选是 O(N)】')

r.cmd('FLUSHALL')
print('  写入 10 万条订单（JSON，含 amount 字段）')
for i in range(0, 100000, 2000):
    cmds = []
    for j in range(2000):
        uid = i + j
        cmds.append(('SET', 'order:%d' % uid,
                     json.dumps({'uid': uid, 'amount': uid % 10000,
                                 'city': 'city%d' % (uid % 50)})))
    r.pipeline(cmds)
print('  DBSIZE = %d' % r.cmd('DBSIZE'))

print('\n  需求：找出 amount > 9000 的订单')
print('  数据库里：SELECT * FROM orders WHERE amount > 9000  （走索引，毫秒级）')
print('  Redis 原生：没有「按字段查询」能力，只能全量取回客户端过滤\n')

t0 = time.time()
matched = 0
fetched = 0
for i in range(0, 100000, 2000):
    ks = ['order:%d' % (i + j) for j in range(2000)]
    vals = r.cmd('MGET', *ks)
    for v in vals:
        fetched += 1
        if v is None:
            continue
        d = json.loads(v.decode() if isinstance(v, bytes) else v)
        if d['amount'] > 9000:
            matched += 1
dt = time.time() - t0
print('  实测：取回 %d 条并过滤，耗时 %.2f 秒，命中 %d 条' % (fetched, dt, matched))
print('  → 命中率只有 %.2f%%，却传输了 100%% 的数据' % (matched * 100.0 / fetched))
print('     这类需求 Redis 原生做不了，是「该用数据库」的明确信号。')

# 对比：Redis 8 有 Query Engine 可以建索引
print('\n  ⚠️ 但 Redis 8 内置了 Query Engine（RediSearch），可以建索引：')
print('     前提：数据必须存成 Hash，且用 FT.CREATE 建索引。')
r.cmd('FLUSHALL')
# 建一批 hash
for i in range(0, 100000, 2000):
    cmds = []
    for j in range(2000):
        uid = i + j
        cmds.append(('HSET', 'ord:%d' % uid, 'uid', uid,
                     'amount', uid % 10000, 'city', 'city%d' % (uid % 50)))
    r.pipeline(cmds)
try:
    r.cmd('FT.CREATE', 'orderidx', 'ON', 'HASH', 'PREFIX', '1', 'ord:',
          'SCHEMA', 'amount', 'NUMERIC', 'SORTABLE', 'city', 'TAG')
    created = True
except lib.RedisError as e:
    created = False
    print('     索引创建失败:', str(e)[:80])

if created:
    import time as _t
    _t.sleep(1.0)  # 等索引建完
    t0 = time.time()
    res = r.cmd('FT.SEARCH', 'orderidx', '@amount:[9000 10000]',
                'RETURN', '1', 'uid', 'LIMIT', '0', '10')
    dt_idx = time.time() - t0
    total = res[0] if res else 0
    print('     FT.SEARCH @amount:[9000 10000]')
    print('     命中总数 = %s，查询耗时 %.4f s' % (total, dt_idx))
    print('     → 建了索引后是毫秒级。但这是在 Redis 里"造了一个小型搜索引擎"，')
    print('       要权衡复杂度：如果只是偶尔做这种查询，放数据库更合适。')

r.cmd('FLUSHALL')

print('\n' + '=' * 66)
print('  实验 5 完成')
print('=' * 66)
r.close()
