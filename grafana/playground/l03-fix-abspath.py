# -*- coding: utf-8 -*-
"""修复课 2 正文里的 /D:/ 绝对路径链接 → 相对路径（幂等）

原因：lesson 文件在 stages/1-看得见/lessons/，距仓库根 3 层，
     playground 在根下，故应为 ../../../playground/xxx
这些链接在 Markdown 渲染时是死链（浏览器打不开 /D:/ 盘符路径）。
课 2 的校验脚本只查了课尾导航链接，未扫正文，故漏网。
"""
import io, re, os, sys

P = '/mnt/d/projects/learning/grafana/stages/1-看得见/lessons/lesson-02-第一个面板：从零到看得见.md'
ROOT = '/mnt/d/projects/learning/grafana'

with io.open(P, encoding='utf-8') as f:
    t = f.read()

def fix(m):
    label, target = m.group(1), m.group(2)
    # 归一 /D:/projects/... 或 D:/projects/... 为仓库内相对路径
    m2 = re.match(r'^/?[A-Za-z]:/projects/learning/grafana/(.+)$', target)
    if not m2:
        return m.group(0)
    inner = m2.group(1)
    rel = os.path.relpath(os.path.join(ROOT, inner), os.path.dirname(P))
    return '[%s](%s)' % (label, rel.replace(os.sep, '/'))

new, n = re.subn(r'\[([^\]]*)\]\(([^)]+)\)', fix, t)
changed = sum(1 for _ in re.finditer(r'\]\(\.\./\.\./\.\./playground/', new))

with io.open(P, 'w', encoding='utf-8') as f:
    f.write(new)

print('处理链接总数 =', n)
print('转换后的 ../../../playground/ 链接数 =', changed)
left = len(re.findall(r'\]\(/[A-Za-z]:', new))
print('剩余的 /D:/ 绝对路径 =', left)
sys.exit(1 if left else 0)
