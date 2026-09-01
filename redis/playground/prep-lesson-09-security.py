#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
实验 2：安全基线 —— 默认配置有多危险 + ACL 加固实战
在独立端口 7101 上演示：无认证暴露面、危险命令、ACL 最小权限、ACL 绕过 CONFIG。
"""
import importlib.util
import time

spec = importlib.util.spec_from_file_location(
    "l09lib", "/mnt/d/projects/learning/redis/playground/prep-lesson-09-lib.py")
lib = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lib)

Redis, section = lib.Redis, lib.section

r = Redis(port=7101)

section('实验 2：安全基线 —— 从「裸奔」到最小权限')

# ---------- 0. 现状：默认配置的风险面 ----------
print('\n【0. 默认配置的风险面】')
print('  当前 ACL 用户：')
acl = r.cmd('ACL', 'LIST')
if isinstance(acl, bytes):
    acl = [acl]
for line in acl:
    l = line.decode() if isinstance(line, bytes) else line
    print('    ' + l)

print('\n  关键安全配置实测：')
for cfg in ['protected-mode', 'bind', 'requirepass', 'enable-debug-command',
            'enable-module-command', 'enable-protected-configs',
            'enable-unprotected-command']:
    v = r.cmd('CONFIG', 'GET', cfg)
    val = v[1] if isinstance(v, list) and len(v) > 1 else '(none)'
    if isinstance(val, bytes):
        val = val.decode()
    print('    %-30s = %s' % (cfg, val if val != '' else '(空 = 未设置)'))

# ---------- 1. 危险命令：证明 default 用户可以为所欲为 ----------
print('\n' + '-' * 66)
print('【1. 危险命令：default 用户 +@all 意味着什么】')

r.cmd('FLUSHALL')
r.cmd('SET', 'asset:config', 'production-db-password-xxx')
r.cmd('SET', 'biz:order:1', 'important')

print('  先写入两条数据：asset:config, biz:order:1')
print('  DBSIZE =', r.cmd('DBSIZE'))

print('\n  用 default 用户（无任何限制）依次尝试危险操作：')

print('\n  (a) FLUSHALL —— 清空整个数据库')
print('      执行前 DBSIZE =', r.cmd('DBSIZE'))
r.cmd('FLUSHALL')
print('      执行后 DBSIZE =', r.cmd('DBSIZE'))
print('      ↑ 一条命令，全部数据消失，且不可撤销')

# 重新写回
r.cmd('MSET', 'asset:config', 'production-db-password-xxx', 'biz:order:1', 'important')

print('\n  (b) CONFIG SET —— 运行时改配置（可被用来关闭保护）')
r.cmd('CONFIG', 'SET', 'maxmemory', '100mb')
print('      CONFIG SET maxmemory 100mb ->', r.cmd('CONFIG', 'GET', 'maxmemory')[1])
r.cmd('CONFIG', 'SET', 'maxmemory', '0')

print('\n  (c) CONFIG SET protected-mode no + bind 改掉 —— 直接对外暴露')
r.cmd('CONFIG', 'SET', 'protected-mode', 'no')
print('      protected-mode 现在是:', r.cmd('CONFIG', 'GET', 'protected-mode')[1])
r.cmd('CONFIG', 'SET', 'protected-mode', 'yes')
print('      （已改回 yes，仅为演示）')

print('\n  (d) KEYS * —— 拖垮服务 + 泄露全部 key 名')
ks = r.cmd('KEYS', '*')
print('      返回 %d 个 key 名，键名本身往往含业务语义（如 asset:config）' % len(ks))
print('      前 5 个:', [k.decode() for k in ks[:5]])

print('\n  ⚠️ 这些命令在 default(+@all) 下全部可用。真实事故里，')
print('     「Redis 未授权访问」的典型利用链就是：')
print('     无密码 → FLUSHALL 勒索 / CONFIG SET dir 写 Webshell / KEYS 拖库')

# ---------- 2. ACL 加固实战 ----------
print('\n' + '-' * 66)
print('【2. ACL 加固实战：三个典型角色】')

print('\n  (a) 创建只读业务用户（缓存读取服务）')
try:
    r.cmd('ACL', 'DELUSER', 'app_ro')
except Exception:
    pass
r.cmd('ACL', 'SETUSER', 'app_ro', 'on', '>ro_password_123',
      '~cache:*', '+get', '+mget', '+ttl', '+exists', '-@all', '+@read')
print('      ACL SETUSER app_ro on >ro_password_123 ~cache:* -@all +@read')
acl = r.cmd('ACL', 'LIST')
if isinstance(acl, bytes):
    acl = [acl]
for line in acl:
    l = line.decode() if isinstance(line, bytes) else line
    if 'app_ro' in l:
        print('      ->', l)

print('\n  (b) 创建可写业务用户（只允许写自己的前缀，禁止管理命令）')
try:
    r.cmd('ACL', 'DELUSER', 'app_rw')
except Exception:
    pass
r.cmd('ACL', 'SETUSER', 'app_rw', 'on', '>rw_password_456',
      '~cache:*', '~biz:*', '-@all', '+@read', '+@write', '-@admin',
      '-@dangerous')
print('      ACL SETUSER app_rw on >rw_password_456 ~cache:* ~biz:* -@all +@read +@write -@admin -@dangerous')

print('\n  (c) 创建运维用户（允许管理命令但禁止删数据）')
try:
    r.cmd('ACL', 'DELUSER', 'ops')
except Exception:
    pass
r.cmd('ACL', 'SETUSER', 'ops', 'on', '>ops_password_789',
      '~*', '-@all', '+@read', '+@admin', '+@slow', '+info', '+config|get',
      '-flushall', '-flushdb', '-shutdown')
print('      ACL SETUSER ops on >ops_password_789 ~* -@all +@read +@admin +@slow +info +config|get -flushall -flushdb -shutdown')

print('\n  三个用户已建立。下面用实际连接验证权限是否生效。')

# ---------- 3. 用真实连接验证权限 ----------
print('\n' + '-' * 66)
print('【3. 权限验证：用真实连接逐个试】')

def try_as(user, pwd, cmds, label):
    print('\n  --- 以 %s 身份连接 ---' % label)
    try:
        c = Redis(port=7101)
        c.cmd('AUTH', user, pwd)
        print('      AUTH %s -> OK' % user)
    except Exception as e:
        print('      AUTH 失败: %s' % e)
        return
    for cmd in cmds:
        try:
            res = c.cmd(*cmd)
            if isinstance(res, bytes):
                res = res.decode('utf-8', 'replace')
            if isinstance(res, list):
                res = [x.decode('utf-8', 'replace') if isinstance(x, bytes) else x
                       for x in res]
                if len(res) > 4:
                    res = res[:4] + ['...(%d total)' % len(res)]
            print('      %-42s -> %s' % (' '.join(str(x) for x in cmd), res))
        except lib.RedisError as e:
            msg = str(e)
            if len(msg) > 70:
                msg = msg[:70] + '...'
            print('      %-42s -> DENIED: %s' % (' '.join(str(x) for x in cmd), msg))
    c.close()

# 准备数据
r.cmd('MSET', 'cache:a', '1', 'biz:b', '2', 'asset:secret', 'top-secret')

try_as('app_ro', 'ro_password_123', [
    ('GET', 'cache:a'),          # 允许：前缀匹配 + @read
    ('GET', 'asset:secret'),     # 拒绝：前缀不匹配
    ('SET', 'cache:a', '9'),     # 拒绝：只读用户
    ('FLUSHALL',),               # 拒绝
    ('KEYS', '*'),               # 拒绝：@keyspace 被 -@all 排除
], 'app_ro（只读）')

try_as('app_rw', 'rw_password_456', [
    ('GET', 'cache:a'),          # 允许
    ('SET', 'cache:a', '9'),     # 允许：@write
    ('SET', 'asset:hack', 'x'),  # 拒绝：前缀不匹配
    ('FLUSHALL',),               # 拒绝：-@dangerous
    ('CONFIG', 'GET', 'maxmemory'),  # 拒绝：-@admin
    ('SHUTDOWN',),               # 绝对不能执行，跳过
], 'app_rw（读写）')

print('\n  --- 以 ops 身份连接 ---')
try:
    c = Redis(port=7101)
    c.cmd('AUTH', 'ops', 'ops_password_789')
    print('      AUTH ops -> OK')
    for cmd in [('CONFIG', 'GET', 'maxmemory'),
                ('INFO', 'server'),
                ('SLOWLOG', 'GET', '1'),
                ('GET', 'asset:secret'),
                ('FLUSHALL',)]:
        try:
            res = c.cmd(*cmd)
            if isinstance(res, bytes):
                res = res.decode('utf-8', 'replace')[:70]
            print('      %-40s -> OK (%s)' % (' '.join(cmd), str(res)[:60]))
        except lib.RedisError as e:
            print('      %-40s -> DENIED: %s' % (' '.join(cmd), str(e)[:60]))
    c.close()
except Exception as e:
    print('      AUTH 失败: %s' % e)

# ---------- 4. ACL 的边界：它防不住的 ----------
print('\n' + '-' * 66)
print('【4. ACL 的边界：有些东西它防不住】')

print('\n  (a) 有 @write 权限的用户仍能制造大 key 打爆内存')
print('      这是 ACL 无法阻止的 —— 权限系统管的是「能不能执行」，')
print('      不管「执行了会不会拖垮服务」。要靠 maxmemory + 监控兜底。')

print('\n  (b) DEBUG 命令：默认已禁用（这是好事）')
v = r.cmd('CONFIG', 'GET', 'enable-debug-command')
print('      enable-debug-command = %s' % (v[1] if len(v) > 1 else '(none)'))
try:
    r.cmd('DEBUG', 'SLEEP', '0.1')
    print('      DEBUG SLEEP -> 可执行')
except lib.RedisError as e:
    print('      DEBUG SLEEP -> DENIED: %s' % str(e)[:80])
print('      ↑ 注意：DEBUG 是 enable-debug-command 控制的，不是 ACL 控制的。')
print('        课 8 我们曾用 CONFIG SET enable-debug-command local 打开它。')

print('\n  (c) 慢命令（KEYS / HGETALL）在 ACL 里属于 @keyspace / @read')
print('      给业务账号 +@read 就等于给了 KEYS。要禁得显式 -keys：')
try:
    r.cmd('ACL', 'DELUSER', 'app_safe')
except Exception:
    pass
r.cmd('ACL', 'SETUSER', 'app_safe', 'on', '>safe_pwd', '~cache:*',
      '-@all', '+@read', '-keys', '-hgetall')
c = Redis(port=7101)
c.cmd('AUTH', 'app_safe', 'safe_pwd')
for cmd in [('GET', 'cache:a'), ('KEYS', '*'), ('HGETALL', 'big:hash')]:
    try:
        res = c.cmd(*cmd)
        print('      %-30s -> OK' % ' '.join(cmd))
    except lib.RedisError as e:
        print('      %-30s -> DENIED: %s' % (' '.join(cmd), str(e)[:50]))
c.close()

# ---------- 5. 清理 ----------
print('\n' + '-' * 66)
print('【5. 清理测试用户】')
for u in ['app_ro', 'app_rw', 'ops', 'app_safe']:
    try:
        r.cmd('ACL', 'DELUSER', u)
        print('  已删除用户 %s' % u)
    except Exception as e:
        print('  删除 %s 失败: %s' % (u, e))
r.cmd('FLUSHALL')

print('\n' + '=' * 66)
print('  实验 2 完成')
print('=' * 66)
r.close()
