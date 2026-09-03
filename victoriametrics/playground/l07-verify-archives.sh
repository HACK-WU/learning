#!/bin/bash
# 确认课 7 四处档案回写的实际落盘情况
cd /mnt/d/projects/learning/victoriametrics || exit 1

echo "===== 1. 00-学习档案.md ====="
grep -n '课 7' 00-学习档案.md | head -6
echo
echo "===== 2. 00-评审清单.md ====="
grep -n '课 7' 00-评审清单.md | head -4
echo
echo "===== 3. 阶段 3 概览 ====="
grep -n '课 7\|收官\|65.5' 'stages/3-凭什么快凭什么省/README.md' | head -8
echo
echo "===== 4a. 课程目录 ====="
grep -n '7-内存模型与容量规划' 02-课程目录.md
echo
echo "===== 4b. 学习路径总览 ====="
grep -n '课 7\|已完成 7 课\|23 个' 01-学习路径总览.md | head -6
