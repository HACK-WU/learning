#!/bin/bash
# 定位课 6 讲义「常见误区」章节的准确行号与内容
F='/mnt/d/projects/learning/victoriametrics/stages/3-凭什么快凭什么省/6-压缩为什么能省7倍空间.md'
echo "=== 常见误区章节起始行 ==="
grep -n '^## 🐞 常见误区' "$F"
echo
echo "=== 该章节下的 ### 条目 ==="
awk '/^## 🐞 常见误区/,/^## 🚀/' "$F" | grep -n '^### '
echo
echo "=== 误区 5 的完整内容（含行号）==="
awk 'NR>=1 && /^### 5\./,/^---$/' "$F" | head -20
