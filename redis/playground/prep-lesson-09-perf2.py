#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
实验 3b：补测 perf.py 中断的两节
(5) maxmemory 保护：不设限 vs 设限
(6) 客户端输出缓冲区
"""
import importlib.util
import time
import threading

spec = importlib.util.spec_from_file_location(
    "l09lib", "/mnt/d/projects/learning/redis/playground/prep-lesson-09-lib.py")
lib = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lib)

Redis, section, fmt_bytes = lib.Redis, lib.section, lib.fmt_bytes

r = Redis(port=7101)

section('实验 3b：maxmemory 保护与客户端缓冲区')

# ---------- 5. maxmemory ----------
print('\n【5. maxmemory：设与不设的差别】')

print('\n  当前配置：')
print('    maxmemory        =', r.cmd('CONFIG', 'GET', 'maxmemory')[1], '(0 = 不限制)')
print('    maxmemory-policy =', r.cmd('CONFIG', 'GET', 'maxmemory-policy')[1])

print('\n  ⚠️ 不设 maxmemory 意味着 Redis 会一直吃内存，直到：')
print('     - 触发系统 OOM Killer 被杀掉')
print('     - 或 fork 失败导致无法持久化')
print('     本机不实际触发 OOM（会拖垮系统），改为演示「设限后的可控行为」。')

r.cmd('FLUSHALL')
r.cmd('CONFIG', 'SET', 'maxmemory', '20mb')
r.cmd('CONFIG', 'SET', 'maxmemory-policy', 'allkeys-lru')
print('\n    已设 maxmemory=20mb, policy=allkeys-lru')

ok = fail = 0
i = 0
TOTAL = 300000
while i < TOTAL:
    cmds = [('SET', 'm:k:%d' % (i + j), 'z' * 200) for j in range(1000)]
    res = r.pipeline(cmds)
    ok += sum(1 for x in res if not isinstance(x, lib.RedisError))
    fail += sum(1 for x in res if isinstance(x, lib.RedisError))
    i += 1000

info = r.cmd('INFO', 'stats')
if isinstance(info, bytes):
    info = info.decode('utf-8', 'replace')
sd = {}
for l in info.splitlines():
    if ':' in l and not l.startswith('#'):
        k, v = l.split(':', 1)
        sd[k] = v
evicted = int(sd.get('evicted_keys', 0))

minfo = r.cmd('INFO', 'memory')
if isinstance(minfo, bytes):
    minfo = minfo.decode('utf-8', 'replace')
md = {}
for l in minfo.splitlines():
    if ':' in l and not l.startswith('#'):
        k, v = l.split(':', 1)
        md[k] = v
used = int(md.get('used_memory', 0))
peak = int(md.get('used_memory_peak', 0))
dbsize = int(r.cmd('DBSIZE'))

print('\n    写入 %d 个 key（每个 200B 值，理论约 %.1f MB）'
      % (TOTAL, TOTAL * 200 / 1024.0 / 1024.0))
print('    理论数据量         = %s' % fmt_bytes(TOTAL * 200))
print('    实际 used_memory   = %s' % fmt_bytes(used))
print('    used_memory_peak   = %s' % fmt_bytes(peak))
print('    DBSIZE             = %d（保留了 %d 个，其余被淘汰）' % (dbsize, dbsize))
print('    evicted_keys       = %d' % evicted)
print('    写入成功 %d 次，失败 %d 次' % (ok, fail))
print('\n    → 有 maxmemory 保护：内存被限制在 20MB 附近，')
print('      代价是 %d 个 key 被淘汰（缓存场景可接受，因为可重建）' % evicted)

# 对比：noeviction 策略下的行为
print('\n  --- 对照：policy=noeviction 时会怎样 ---')
r.cmd('FLUSHALL')
r.cmd('CONFIG', 'SET', 'maxmemory', '20mb')
r.cmd('CONFIG', 'SET', 'maxmemory-policy', 'noeviction')
ok2 = fail2 = 0
i = 0
first_err = None
while i < TOTAL:
    cmds = [('SET', 'n:k:%d' % (i + j), 'z' * 200) for j in range(1000)]
    res = r.pipeline(cmds)
    for x in res:
        if isinstance(x, lib.RedisError):
            fail2 += 1
            if first_err is None:
                first_err = str(x)
        else:
            ok2 += 1
    i += 1000
    if fail2 > 0 and i >= 200000:
        break
print('    写入成功 %d 次，失败 %d 次' % (ok2, fail2))
if first_err:
    print('    首次报错: %s' % first_err[:90])
print('\n    → noeviction 下内存满了就直接拒绝写入（而不是淘汰）。')
print('      这是默认值！生产上必须按业务改掉。')

r.cmd('CONFIG', 'SET', 'maxmemory', '0')
r.cmd('CONFIG', 'SET', 'maxmemory-policy', 'noeviction')
r.cmd('FLUSHALL')

# ---------- 6. 客户端输出缓冲区 ----------
print('\n' + '-' * 66)
print('【6. 客户端输出缓冲区：容易被忽视的 OOM 源】')

v = r.cmd('CONFIG', 'GET', 'client-output-buffer-limit')
print('  client-output-buffer-limit =')
print('    %s' % (v[1].decode() if isinstance(v[1], bytes) else v[1]))
print('\n  三段含义：normal / replica / pubsub')
print('    normal 默认 0 0 0 = 不限制')
print('    pubsub 默认 32mb 8mb 60 = 硬限 32MB，软限 8MB 持续 60 秒')

print('\n  风险场景演示：订阅者消费慢 → 输出缓冲区堆积')
pub = Redis(port=7101)
sub = Redis(port=7101)

# 订阅一个频道但不读取
import queue
received = queue.Queue()

def subscriber():
    s = Redis(port=7101)
    try:
        s.sock.sendall(s._encode('SUBSCRIBE', 'chan'))
        # 订阅确认
        s._decode(); s._decode(); s._decode()
        # 之后不再读取 —— 模拟消费慢的客户端
        time.sleep(6)
    except Exception:
        pass
    finally:
        s.close()

th = threading.Thread(target=subscriber, daemon=True)
th.start()
time.sleep(0.5)

mem_before = int(r.cmd('INFO', 'memory').decode().split('used_memory:')[1].split('\r\n')[0]
                 if isinstance(r.cmd('INFO', 'memory'), bytes) else 0)

# 用另一个连接向频道发大量消息
print('  向 chan 频道发布 2000 条 10KB 消息（订阅者不消费）...')
payload = 'x' * 10240
sent = 0
for i in range(2000):
    try:
        pub.sock.sendall(pub._encode('PUBLISH', 'chan', payload))
        sent += 1
    except Exception:
        break
time.sleep(1.0)

cl = r.cmd('CLIENT', 'LIST')
if isinstance(cl, bytes):
    cl = cl.decode('utf-8', 'replace')
print('\n  CLIENT LIST 中的订阅者信息：')
for line in cl.splitlines():
    if 'cmd=subscribe' in line or 'cmd=SUBSCRIBE' in line:
        for kv in line.split(' '):
            if kv.startswith(('obl=', 'omem=', 'cmd=', 'idle=')):
                print('    %s' % kv)

info = r.cmd('INFO', 'memory')
if isinstance(info, bytes):
    info = info.decode('utf-8', 'replace')
md2 = {}
for l in info.splitlines():
    if ':' in l:
        k, v = l.split(':', 1)
        md2[k] = v
print('\n  发布 %d 条后：' % sent)
print('    used_memory_human = %s' % md2.get('used_memory_human'))
print('    → 这些内存不是 key 占的，是客户端输出缓冲区。')
print('      「Redis 内存涨了但 key 没变多」时，先查 CLIENT LIST 的 omem。')

# 触发保护
print('\n  继续发布直到触发 pubsub 硬限制（32MB）...')
for i in range(20000):
    try:
        pub.sock.sendall(pub._encode('PUBLISH', 'chan', payload))
    except Exception:
        break
time.sleep(1.5)
cl2 = r.cmd('CLIENT', 'LIST')
if isinstance(cl2, bytes):
    cl2 = cl2.decode('utf-8', 'replace')
still = 'cmd=subscribe' in cl2 or 'cmd=SUBSCRIBE' in cl2
print('    订阅者是否还在: %s' % ('在' if still else '已被断开（触发保护）'))

pub.close()
sub.close()
th.join(timeout=2)
r.cmd('FLUSHALL')

print('\n' + '=' * 66)
print('  实验 3b 完成')
print('=' * 66)
r.close()
