#!/usr/bin/env bash
# 查看评审清单的评审记录表区域（截断每行以便阅读）
set -u
P="/mnt/d/projects/learning/victoriametrics/00-评审清单.md"
echo "=== 总行数: $(grep -c '' "$P") ==="
echo
echo "=== 第 54 行起 ==="
awk 'NR>=54' "$P" | cut -c1-95
