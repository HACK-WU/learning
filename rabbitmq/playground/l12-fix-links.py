#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
批量修复：各课讲义中「返回课程目录」链接的层级错误。

问题：讲义位于 stages/<阶段>/lessons/ 下，到项目根需要三级 ../../../
      但课 2/3/4/5/6 写成了两级 ../../  → 链接指向 stages/02-课程目录.md（不存在）
      课 7 是正确的（../../../），不受影响。

本脚本只做这一处精确替换，并逐文件校验替换后链接真实存在。
"""
import os
import sys

BASE = '/mnt/d/projects/learning/rabbitmq'
STAGES = BASE + '/stages'

OLD = '](../../02-课程目录.md)'
NEW = '](../../../02-课程目录.md)'

changed = []
skipped = []


def main():
    for stage in sorted(os.listdir(STAGES)):
        lesson_dir = os.path.join(STAGES, stage, 'lessons')
        if not os.path.isdir(lesson_dir):
            continue
        for fn in sorted(os.listdir(lesson_dir)):
            if not fn.endswith('.md'):
                continue
            path = os.path.join(lesson_dir, fn)
            with open(path, encoding='utf-8') as f:
                text = f.read()
            if OLD not in text:
                continue
            n = text.count(OLD)
            new_text = text.replace(OLD, NEW)
            # 校验：替换后目标必须存在
            target = os.path.normpath(
                os.path.join(os.path.dirname(path), '../../../02-课程目录.md'))
            if not os.path.exists(target):
                skipped.append('%s → 替换后仍无效：%s' % (fn, target))
                continue
            with open(path, 'w', encoding='utf-8') as f:
                f.write(new_text)
            changed.append('%s（%d 处）' % (fn, n))

    print("=" * 72)
    print("修复课程目录链接层级")
    print("=" * 72)
    print("")
    if changed:
        print("已修改：")
        for c in changed:
            print("  ✅ %s" % c)
    else:
        print("  无需修改的文件")
    if skipped:
        print("\n跳过：")
        for s in skipped:
            print("  ⚠️ %s" % s)
    print("")
    print("=" * 72)
    return 0


if __name__ == '__main__':
    sys.exit(main())
