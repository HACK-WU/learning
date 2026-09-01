#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
排查：FT.SEARCH 命中 7677 vs 全量扫描 9990，哪个对？
假设：索引尚未构建完成就查询（后台异步建索引），导致结果偏少。
"""
import importlib.util
import time

spec = importlib.util.spec_from_file_location(
    "l09lib", "/mnt/d/projects/learning/redis/playground/prep-lesson-09-lib.py")
lib = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lib)

Redis, section = lib.Redis, lib.section

r = Redis(port=7106)

section('排查：索引命中数不等于真实命中数')

r.cmd('FLUSHALL')
N = 100000
for i in range(0, N, 2000):
    cmds = []
    for j in range(2000):
        uid = i + j
        cmds.append(('HSET', 'ord:%d' % uid, 'uid', uid,
                     'amount', uid % 10000, 'city', 'city%d' % (uid % 50)))
    r.pipeline(cmds)
print('  写入 %d 条' % r.cmd('DBSIZE'))

# 真实值：精确计算 amount > 9000 的条数
# amount = uid % 10000, uid in [0, 100000)
# uid % 10000 > 9000  ->  uid % 10000 in [9001, 9999]
truth = sum(1 for uid in range(N) if uid % 10000 > 9000)
print('  数学真值（uid %% 10000 > 9000）= %d 条' % truth)

# 全量扫描确认
cnt = 0
for i in range(0, N, 2000):
    ks = ['ord:%d' % (i + j) for j in range(2000)]
    vals = r.pipeline([('HMGET', k, 'amount') for k in ks])
    for v in vals:
        if v and v[0] is not None and int(v[0]) > 9000:
            cnt += 1
print('  全量扫描实测          = %d 条' % cnt)

# 建索引
try:
    r.cmd('FT.DROPINDEX', 'orderidx')
except Exception:
    pass
r.cmd('FT.CREATE', 'orderidx', 'ON', 'HASH', 'PREFIX', '1', 'ord:',
      'SCHEMA', 'amount', 'NUMERIC', 'SORTABLE', 'city', 'TAG')

print('\n  建索引后立刻查询（不等）：')
res = r.cmd('FT.SEARCH', 'orderidx', '@amount:[9000 10000]', 'LIMIT', '0', '0')
print('    命中 = %s' % res[0])

print('\n  等待索引构建完成，每 0.5s 查一次：')
for i in range(20):
    time.sleep(0.5)
    res = r.cmd('FT.SEARCH', 'orderidx', '@amount:[9000 10000]', 'LIMIT', '0', '0')
    n = res[0]
    print('    t=%.1fs  命中 = %s' % ((i + 1) * 0.5, n))
    if int(n) == truth:
        print('    ↑ 索引构建完成，与真值一致')
        break

# FT.INFO 查看索引状态
print('\n  FT.INFO 关键字段：')
try:
    info = r.cmd('FT.INFO', 'orderidx')
    # info 是 flat list
    d = {}
    for i in range(0, len(info) - 1, 2):
        k = info[i]
        if isinstance(k, bytes):
            k = k.decode()
        d[k] = info[i + 1]
    for key in ['index_name', 'num_docs', 'num_records', 'hash_indexing_failures',
                'indexing', 'percent_indexed']:
        if key in d:
            v = d[key]
            print('    %-24s = %s' % (key, v))
except Exception as e:
    print('    FT.INFO 失败: %s' % e)

print('\n  结论：RediSearch 的索引是【异步后台构建】的。')
print('        FT.CREATE 返回 OK 只代表索引定义创建成功，不代表数据已索引完。')
print('        生产上必须通过 FT.INFO 的 percent_indexed 确认就绪后再切流量。')

r.cmd('FT.DROPINDEX', 'orderidx')
r.cmd('FLUSHALL')
r.close()
