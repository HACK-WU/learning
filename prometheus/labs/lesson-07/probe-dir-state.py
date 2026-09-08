#!/usr/bin/env python3
"""用 Python 直接从 Windows 文件系统层面检查目录状态（绕开 bash 的挂载视图）。"""
import os

base = r'D:/projects/learning/prometheus/labs/lesson-07'
print("=== lesson-07 目录实际内容（Python 视角） ===")
print(f"路径存在: {os.path.exists(base)}")
print(f"是目录  : {os.path.isdir(base)}")
print()

if os.path.isdir(base):
    items = sorted(os.listdir(base))
    print(f"共 {len(items)} 项：")
    for n in items:
        p = os.path.join(base, n)
        if os.path.isdir(p):
            sub = os.listdir(p)
            print(f"  [DIR ] {n}/  ({len(sub)} 项: {sub[:5]})")
        else:
            print(f"  [FILE] {n}  ({os.path.getsize(p)} 字节)")
else:
    print("目录不存在！")

print()
print("=== 检查 labs 下的其他课 ===")
labs = r'D:/projects/learning/prometheus/labs'
if os.path.isdir(labs):
    for n in sorted(os.listdir(labs)):
        p = os.path.join(labs, n)
        cnt = len(os.listdir(p)) if os.path.isdir(p) else 0
        print(f"  {n}: {'目录' if os.path.isdir(p) else '文件'} ({cnt} 项)")
