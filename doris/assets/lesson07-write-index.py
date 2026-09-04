import io

base = '/mnt/d/projects/learning/doris/'
L7 = 'stages/3-数据导入与查询/lessons/lesson-07-查询引擎与执行计划.md'

# ---------- 1. 02-课程目录.md ----------
p = base + '02-课程目录.md'
s = io.open(p, encoding='utf-8').read()

# 补修课 6：此前只加了链接，忘了标 ✅（课 6 交付时的索引遗漏）
old6 = '### [课 6：数据导入全家桶](stages/3-数据导入与查询/lessons/lesson-06-数据导入全家桶.md)（未编写）'
new6 = '### [课 6：数据导入全家桶](stages/3-数据导入与查询/lessons/lesson-06-数据导入全家桶.md) ✅'
assert old6 in s, 'lesson6 row not found'
s = s.replace(old6, new6)

old7 = '### 课 7：查询引擎与执行计划（未编写）'
new7 = '### [课 7：查询引擎与执行计划](' + L7 + ') ✅'
assert old7 in s, 'lesson7 row not found'
s = s.replace(old7, new7)

io.open(p, 'w', encoding='utf-8').write(s)
print('catalog done')

# ---------- 2. 01-学习路径总览.md ----------
p = base + '01-学习路径总览.md'
s = io.open(p, encoding='utf-8').read()

old = '- [ ] 阶段 3：数据导入与查询（**进行中**：课 6 已完成 2026-09-02，课 7 / 课 8 待交付）'
new = '- [ ] 阶段 3：数据导入与查询（**进行中**：课 6、课 7 已完成 2026-09-02，课 8 待交付）'
assert old in s, 'stage3 progress not found'
s = s.replace(old, new)

old = '**总进度**：18 / 36 知识点已完成（2026-09-02 更新）'
new = '**总进度**：21 / 36 知识点已完成（2026-09-02 更新）'
assert old in s, 'total progress not found'
s = s.replace(old, new)

io.open(p, 'w', encoding='utf-8').write(s)
print('overview-index done')
