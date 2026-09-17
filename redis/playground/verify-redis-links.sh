#!/usr/bin/env bash
# 校验 redis 目录下 Markdown 相对链接可达性（逐条打印依据，便于人工复核）
python3 - <<'PY'
import os, re
root = '/mnt/d/projects/learning/redis'
bad = []
n = 0
for dp, dn, fn in os.walk(root):
    for f in fn:
        if not f.endswith('.md'):
            continue
        p = os.path.join(dp, f)
        n += 1
        txt = open(p, encoding='utf-8').read()
        for m in re.finditer(r'\]\((\.\.?[^)#]+\.md)\)', txt):
            rel = m.group(1)
            t = os.path.normpath(os.path.join(dp, rel))
            if not os.path.exists(t):
                bad.append((os.path.relpath(p, root), rel, t))
print('scanned', n, 'md files')
if not bad:
    print('ALL_LINKS_OK')
else:
    print('BROKEN %d:' % len(bad))
    for src, rel, t in bad:
        print('  源:', src)
        print('  链接:', rel)
        print('  解析为:', t)
        print('  存在?', os.path.exists(t))
        print()
PY
echo "===== 人工复核：被报断链的目标文件是否真的存在 ====="
for p in \
  "/mnt/d/projects/learning/redis/02-课程目录.md" \
  "/mnt/d/projects/learning/redis/stages/02-课程目录.md" \
  "/mnt/d/projects/learning/redis/stages/1-为什么需要Redis/lessons/lesson-02-跑起来第一个Redis.md" \
  "/mnt/d/projects/learning/redis/stages/2-数据结构与命令/1-为什么需要Redis/lessons/lesson-02-跑起来第一个Redis.md" \
  "/mnt/d/projects/learning/redis/stages/3-持久化与高可用/lessons/lesson-06-主从复制与哨兵.md" \
  "/mnt/d/projects/learning/redis/stages/4-分布式与生产实践/3-持久化与高可用/lessons/lesson-06-主从复制与哨兵.md" ; do
  if [ -e "$p" ]; then echo "EXISTS   $p"; else echo "MISSING  $p"; fi
done
