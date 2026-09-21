# -*- coding: utf-8 -*-
"""实战 E 篇终验：交付物 + 口径统一 + 链接"""
import os, re, sys, xml.etree.ElementTree as ET

ROOT = '/mnt/d/projects/learning/consul'
E = os.path.join(ROOT, 'practices/实战E-北向网关与真实数据面')
PASS, FAIL = [], []

def ck(cond, label):
    (PASS if cond else FAIL).append(label)
    print(('  OK   ' if cond else '  FAIL ') + label)

def rd(p):
    return open(os.path.join(ROOT, p), encoding='utf-8').read() if os.path.exists(os.path.join(ROOT, p)) else ''

def has(p, s, label):
    ck(s in rd(p), label)

print('=' * 60)
print('1. E 篇交付物')
print('=' * 60)
ck(os.path.isdir(E), 'E 篇目录存在')
readme = os.path.join(E, 'README.md')
ck(os.path.exists(readme), 'E 篇 README.md 存在')
txt = rd('practices/实战E-北向网关与真实数据面/README.md')
ck(len(txt) > 6000, 'README 篇幅 %d 字' % len(txt))
for s in ['## 场景 1', '## 场景 2', '## 场景 3', '🎯 会用标志', '📎 实测证据', '仍存在的已知边界', '🧭 导航']:
    ck(s in txt, '含节: %s' % s)

# SVG
svgdir = os.path.join(E, 'assets')
svgs = sorted([f for f in os.listdir(svgdir) if f.endswith('.svg')]) if os.path.isdir(svgdir) else []
ck(len(svgs) == 3, 'SVG 数量 = %d (期望3)' % len(svgs))
for f in svgs:
    fp = os.path.join(svgdir, f)
    try:
        ET.parse(fp); okxml = True
    except Exception:
        okxml = False
    ck(okxml, 'SVG 合法: %s' % f)
    ck(('./assets/%s' % f) in txt, 'README 引用: %s' % f)

print()
print('=' * 60)
print('2. E 篇内容断言（实测结论必须在场）')
print('=' * 60)
facts = [
 ('Kind 必须带', 'ingress-gateway"'),
 ('grpc-ca-file', '-grpc-ca-file'),
 ('Host 头', 'web.ingress'),
 ('404 现象', '404'),
 ('503 现象', '503'),
 ('50/50 实测', 'V1=16'),
 ('权重热更新', 'V1=22'),
 ('deny 未拦截', 'V2 命中 11'),
 ('DENY 策略 False', 'DENY 策略'),
 ('setsid', 'setsid'),
 ('Docker', 'docker run'),
 ('Envoy 版本', '1.37.6'),
 ('权重和校验', 'must be 100'),
]
for label, s in facts:
    ck(s in txt, '含实测事实: %s' % label)

print()
print('=' * 60)
print('3. 口径统一（五篇）')
print('=' * 60)
has('final-课程手册.md', '应用实战 5 篇', '手册头部 5 篇')
has('final-课程手册.md', '## 五、应用实战五篇', '手册第五节 五篇')
has('final-课程手册.md', '实战E-北向网关与真实数据面', '手册含 E 篇条目')
has('02-课程目录.md', '实战五篇', '课程目录 五篇')
has('00-学习档案.md', '实战五篇', '学习档案 五篇')
has('应用实战篇-逐课判定.md', '五篇均遵守课程铁律', '逐课判定 五篇')
has('应用实战/INDEX.md', '配套 5 篇', 'INDEX 配套 5 篇')
has('应用实战/INDEX.md', '实战E-北向网关与真实数据面', 'INDEX 含 E 行')
has('应用实战/INDEX.md', '- **E 篇**：', 'INDEX 含 E 结论')

# 反向扫描：不应残留"四篇/4 篇"
print()
print('  -- 反向扫描残留 --')
for p in ['final-课程手册.md', '02-课程目录.md', '00-学习档案.md', '应用实战/INDEX.md', '应用实战篇-逐课判定.md']:
    c = rd(p)
    bad = re.findall(r'实战四篇|应用实战 4 篇|配套 4 篇|四篇均|四篇均为', c)
    ck(not bad, '无残留四篇: %s %s' % (p, bad if bad else ''))

print()
print('=' * 60)
print('4. D 篇边界已指向 E 篇')
print('=' * 60)
d = rd('practices/实战D-灰度发布与流量切分/README.md')
ck('实战E-北向网关与真实数据面' in d, 'D 篇引用 E 篇')
ck('已由 E 篇兑现' in d, 'D 篇标注边界已兑现')

print()
print('=' * 60)
print('5. 相对链接校验（E 篇 + 改动文件）')
print('=' * 60)
targets = ['practices/实战E-北向网关与真实数据面/README.md', 'practices/实战D-灰度发布与流量切分/README.md',
           'final-课程手册.md', '应用实战/INDEX.md', '02-课程目录.md', '00-学习档案.md',
           '应用实战篇-逐课判定.md']
total = 0
for rel in targets:
    fp = os.path.join(ROOT, rel)
    if not os.path.exists(fp):
        ck(False, '文件存在: %s' % rel); continue
    base = os.path.dirname(fp)
    content = open(fp, encoding='utf-8').read()
    links = re.findall(r'\]\((\.[^)#]+?)\)', content)
    bad = []
    for l in links:
        lp = l.split('#')[0]
        if not lp: continue
        full = os.path.normpath(os.path.join(base, lp))
        if not os.path.exists(full): bad.append(l)
        total += 1
    ck(not bad, '%s: %d 条链接 %s' % (os.path.basename(rel), len(links), bad if bad else '全部可达'))
print('  合计校验 %d 条链接' % total)

print()
print('=' * 60)
print('汇总：%d PASS / %d FAIL' % (len(PASS), len(FAIL)))
print('=' * 60)
if FAIL:
    print('未通过项:')
    for f in FAIL: print('  - ' + f)
    sys.exit(1)
print('  全部通过')
