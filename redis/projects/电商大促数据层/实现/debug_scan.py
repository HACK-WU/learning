#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""定位 scan_all 死循环：检查游标返回类型"""
import sys
sys.path.insert(0, '.')
from redislib import conn_master

r = conn_master()
print('DBSIZE =', r.cmd('DBSIZE'))

cur = 0
rounds = 0
total = 0
while rounds < 8:
    res = r.cmd('SCAN', cur, 'MATCH', '*', 'COUNT', 500)
    rounds += 1
    print('  第%d轮: 返回类型=%s, cur=%r (类型%s), 本批 key 数=%d'
          % (rounds, type(res).__name__, res[0], type(res[0]).__name__, len(res[1])))
    total += len(res[1])
    # 关键检查：游标是不是字符串？是字符串的话 '0' != 0，循环永不退出
    if isinstance(res[0], bytes):
        print('    ⚠️ 游标是 bytes！与整数 0 比较永远不等 → 死循环')
        cur = res[0]
        if res[0] == b'0':
            print('    遇到 b"0"，跳出')
            break
    else:
        cur = res[0]
        if cur == 0:
            break

print('\n总共 %d 轮，累计 key %d 个' % (rounds, total))
