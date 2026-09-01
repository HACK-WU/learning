#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
实验 6：Redis 8 Query Engine（RediSearch）——「不该用 Redis」的边界在哪里
对比：全量扫描过滤 vs 建索引查询
同时给出选型判据：什么时候该在 Redis 里造索引，什么时候该回数据库。
"""
import importlib.util
import time
import json

spec = importlib.util.spec_from_file_location(
    "l09lib", "/mnt/d/projects/learning/redis/playground/prep-lesson-09-lib.py")
lib = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lib)

Redis, section, fmt_bytes = lib.Redis, lib.section, lib.fmt_bytes

PORT = 7106
r = Redis(port=PORT)

section('实验 6：Query Engine —— Redis 的能力边界')

print('\n【1. 准备 10 万条订单（存为 Hash，便于建索引）】')
r.cmd('FLUSHALL')
N = 100000
t0 = time.time()
for i in range(0, N, 2000):
    cmds = []
    for j in range(2000):
        uid = i + j
        cmds.append(('HSET', 'ord:%d' % uid, 'uid', uid,
                     'amount', uid % 10000, 'city', 'city%d' % (uid % 50)))
    r.pipeline(cmds)
print('  DBSIZE = %d，写入耗时 %.2f s' % (r.cmd('DBSIZE'), time.time() - t0))

print('\n【2. 无索引：全量取回客户端过滤】')
t0 = time.time()
matched = 0
for i in range(0, N, 2000):
    ks = ['ord:%d' % (i + j) for j in range(2000)]
    vals = r.pipeline([('HMGET', k, 'uid', 'amount') for k in ks])
    for v in vals:
        if v and v[1] is not None:
            if int(v[1]) > 9000:
                matched += 1
dt_scan = time.time() - t0
print('  命中 %d 条，耗时 %.3f s' % (matched, dt_scan))
print('  → 传输了 10 万条，只用到 %d 条（%.1f%%）'
      % (matched, matched * 100.0 / N))

print('\n【3. 建索引后查询】')
try:
    r.cmd('FT.DROPINDEX', 'orderidx')
except Exception:
    pass
t0 = time.time()
t_create_start = time.time()
r.cmd('FT.CREATE', 'orderidx', 'ON', 'HASH', 'PREFIX', '1', 'ord:',
      'SCHEMA', 'amount', 'NUMERIC', 'SORTABLE', 'city', 'TAG')
dt_create = time.time() - t_create_start

# ⚠️ 关键：索引是异步后台构建的，FT.CREATE 返回不代表数据已就绪
# 必须轮询 FT.INFO 的 percent_indexed 等待就绪，否则命中数会严重偏少
print('  FT.CREATE 返回 OK，但索引正在后台异步构建 ...')
ready_at = None
for i in range(60):
    time.sleep(0.2)
    info = r.cmd('FT.INFO', 'orderidx')
    d = {}
    for j in range(0, len(info) - 1, 2):
        k = info[j]
        d[k.decode() if isinstance(k, bytes) else k] = info[j + 1]
    pct = d.get('percent_indexed', b'0')
    pct = float(pct.decode() if isinstance(pct, bytes) else pct)
    if pct >= 1.0:
        ready_at = (i + 1) * 0.2
        break
if ready_at:
    print('  索引构建完成，耗时约 %.1f s（此时 percent_indexed=1）' % ready_at)
else:
    print('  ⚠️ 等待超时')

# 查询条件 (9000, 10000]：RediSearch 的 NUMERIC 区间是闭区间，
# 用 [(9000 (10000] 表示开区间左端点，等价于 SQL 的 amount > 9000
t0 = time.time()
res = r.cmd('FT.SEARCH', 'orderidx', '@amount:[(9000 (10000]',
            'RETURN', '1', 'uid', 'LIMIT', '0', '10')
dt_search = time.time() - t0
total = res[0]
print('  建索引耗时 %.3f s（返回时间，不含后台构建）' % dt_create)
print('  FT.SEARCH @amount:[(9000 (10000]')
print('    命中总数 = %s' % total)
print('    查询耗时 = %.4f s' % dt_search)
print('  → 比全量扫描快 %.0f 倍' % (dt_scan / dt_search))

print('\n【4. 索引的内存代价】')
info = r.cmd('INFO', 'memory')
if isinstance(info, bytes):
    info = info.decode('utf-8', 'replace')
d = {}
for l in info.splitlines():
    if ':' in l and not l.startswith('#'):
        k, v = l.split(':', 1)
        d[k] = v
used_with_idx = int(d.get('used_memory', 0))

r.cmd('FT.DROPINDEX', 'orderidx')
time.sleep(0.5)
info = r.cmd('INFO', 'memory')
if isinstance(info, bytes):
    info = info.decode('utf-8', 'replace')
d2 = {}
for l in info.splitlines():
    if ':' in l and not l.startswith('#'):
        k, v = l.split(':', 1)
        d2[k] = v
used_no_idx = int(d2.get('used_memory', 0))
print('  有索引 = %s，无索引 = %s' % (fmt_bytes(used_with_idx), fmt_bytes(used_no_idx)))
print('  → 索引额外占 %s（约数据的 %.1f%%）'
      % (fmt_bytes(used_with_idx - used_no_idx),
         (used_with_idx - used_no_idx) * 100.0 / used_no_idx))

print('\n【5. 结论：这个索引该不该建？】')
print('''  判据不是"能不能建"，而是"值的复杂度是否值得"：

  建（留在 Redis）：
    - 这个查询是高频主路径（每次请求都要做）
    - 数据本身就是 Redis 里的主数据（不是数据库的热副本）
    - 能接受索引的内存与维护成本

  不建（回数据库）：
    - 只是偶发的运营查询/后台导出
    - 数据在数据库里已有合适索引
    - 团队不具备维护 Redis 索引的经验

  Redis 8 把 RediSearch 内置进来，是让"Redis 顺手能做搜索"，
  不是让"所有搜索都该放 Redis"。''')

r.cmd('FLUSHALL')
print('\n' + '=' * 66)
print('  实验 6 完成')
print('=' * 66)
r.close()
