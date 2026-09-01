#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""诊断：内部链接在 WSL 路径下为何判定为不存在。"""
import os

BASE = '/mnt/d/projects/learning/rabbitmq'
DOC = (BASE + '/stages/4-进阶与工程落地/lessons/'
       'lesson-12-架构落地与选型决策.md')

print("cwd:", os.getcwd())
print("DOC exists:", os.path.exists(DOC))
print("BASE exists:", os.path.exists(BASE))

target = os.path.normpath(os.path.join(os.path.dirname(DOC),
                                       '../../02-课程目录.md'))
print("\ntarget:", target)
print("target exists:", os.path.exists(target))

d = os.path.dirname(DOC)
print("\ndirname:", d)
print("dirname exists:", os.path.exists(d))

parent = os.path.dirname(d)
print("\nparent(stage dir):", parent)
print("parent exists:", os.path.exists(parent))

root = os.path.dirname(parent)
print("\nroot:", root)
print("root exists:", os.path.exists(root))
print("root listdir (first 20):")
try:
    print(sorted(os.listdir(root))[:20])
except Exception as e:
    print("  ERROR:", e)
