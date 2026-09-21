# -*- coding: utf-8 -*-
"""校验排障手册新增 5 条的结构完整性与链接"""
import os, re, sys
R = '/mnt/d/projects/learning/consul/'
Q = R + '09-排障速查手册.md'
t = open(Q, encoding='utf-8').read()
PASS, FAIL = [], []

def ck(c, l):
    (PASS if c else FAIL).append(l)
    print(('  OK   ' if c else '  FAIL ') + l)

print('=' * 58)
print('1. 五条条目存在且标题正确')
print('=' * 58)
heads = {
 16: '🔴 症状 16：网关返回 404，但配置明明写好了',
 17: '🔴 症状 17：网关 503，但 Consul 说服务 passing',
 18: '🟡 症状 18：bootstrap 报 TLS/CA 错误（不是网络问题）',
 19: '🟡 症状 19：报 No ingress-gateway services registered（配置写了却说没有）',
 20: '🔴 症状 20：intention deny 写入 200，但流量一次都没拦住',
}
for n, h in heads.items():
    ck(('## %s' % h) in t, '症状 %d 标题' % n)

print()
print('=' * 58)
print('2. 每条必备要素')
print('=' * 58)
# 按症状切段
parts = re.split(r'\n## ', t)
secs = {}
for p in parts:
    m = re.match(r'.{0,3}症状 (\d+)：', p)
    if m: secs[int(m.group(1))] = p
for n in (16, 17, 18, 19, 20):
    s = secs.get(n, '')
    ck('一眼识别' in s, '症状%d 含「一眼识别」' % n)
    ck('为什么会这样' in s, '症状%d 含「为什么会这样」' % n)
    ck('30 秒判断法' in s, '症状%d 含「30 秒判断法」' % n)
    ck('| **止血** |' in s, '症状%d 含止血步骤' % n)
    ck('预防' in s, '症状%d 含预防' % n)
    ck('原理' in s, '症状%d 含原理链接' % n)
    ck('2026-09-21 新增' in s, '症状%d 标注日期' % n)
    ck('本机实测' in s, '症状%d 标注证据来源' % n)

print()
print('=' * 58)
print('3. 症状 20 的诚实纪律（未确认必须显式留痕）')
print('=' * 58)
s20 = secs.get(20, '')
for kw in ['未确认', '根因尚未确认', '疑点', '方法本身是错的', '暂无已验证的修复方案']:
    ck(kw in s20, '症状20 含: %s' % kw)

print()
print('=' * 58)
print('4. 索引表与计数')
print('=' * 58)
for n in (16, 17, 18, 19, 20):
    ck(('**症状 %d**' % n) in t, '索引表含症状 %d' % n)
ck('已收录 20 条' in t, '计数更新为 20 条')
ck('已收录 15 条' not in t, '无残留"已收录 15 条"')
ck('网关问题优先看 16–20' in t, '含网关优先提示')

print()
print('=' * 58)
print('5. 交叉引用有效性（引用的症状号必须真实存在）')
print('=' * 58)
refs = set(int(x) for x in re.findall(r'症状 (\d+)', t))
exist = set(secs.keys())
missing = sorted(refs - exist)
ck(not missing, '引用的症状号均存在 %s' % (missing if missing else ''))

print()
print('=' * 58)
print('6. 新增条目的相对链接可达')
print('=' * 58)
base = os.path.dirname(Q)
new_links = re.findall(r'\]\((\./practices/[^)#]+)\)', t)
bad = [l for l in set(new_links) if not os.path.exists(os.path.normpath(os.path.join(base, l)))]
ck(len(new_links) >= 5, '新链接出现 %d 次（5 条各 1 次）' % len(new_links))
ck(len(set(new_links)) >= 1 and not bad, '新链接可达 %s' % (bad if bad else ''))
ck('practices/实战E-北向网关与真实数据面/README.md' in t, '链接指向 E 篇')

print()
print('=' * 58)
print('汇总：%d PASS / %d FAIL' % (len(PASS), len(FAIL)))
print('=' * 58)
if FAIL:
    for f in FAIL: print('  - ' + f)
    sys.exit(1)
print('  全部通过')
