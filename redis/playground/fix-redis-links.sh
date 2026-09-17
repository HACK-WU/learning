#!/usr/bin/env bash
# 修复 lessons/ 下 Markdown 的相对链接层级错误
# lessons/xxx.md 到 redis/02-课程目录.md 需要 ../../../（三级）
# lessons/xxx.md 到其他阶段需要 ../../N-xxx/（两级到 stages/）
python3 - <<'PY'
import os, re

root = '/mnt/d/projects/learning/redis'
changed = []

for dp, dn, fn in os.walk(root):
    if '/lessons' not in dp.replace('\\', '/'):
        continue
    for f in fn:
        if not f.endswith('.md'):
            continue
        p = os.path.join(dp, f)
        txt = open(p, encoding='utf-8').read()
        orig = txt

        # ① 课程目录：两级 -> 三级
        txt = txt.replace('](../../02-课程目录.md)', '](../../../02-课程目录.md)')
        txt = txt.replace('](../../01-学习路径总览.md)', '](../../../01-学习路径总览.md)')

        # ② 跨阶段/跨目录课链接：一级 -> 两级（仅当指向 stages 下的阶段目录）
        txt = re.sub(
            r'\]\(\.\./(\d-[^/]+)/lessons/',
            r'](../../\1/lessons/',
            txt
        )

        if txt != orig:
            open(p, 'w', encoding='utf-8').write(txt)
            changed.append(os.path.relpath(p, root))

print('已修复文件数：', len(changed))
for c in changed:
    print('  ', c)
PY
