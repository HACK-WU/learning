#!/bin/bash
# 确认 115.7 这个数字在课 5、课 6 中的出现情况
cd /mnt/d/projects/learning/victoriametrics
echo "=== 课 5 中的 115.7 ==="
grep -n '115\.7' 'stages/3-凭什么快凭什么省/5-存储引擎MergeSet与磁盘结构.md' 2>&1 | head -5
echo
echo "=== 课 6 中的 115.7 ==="
grep -n '115\.7' 'stages/3-凭什么快凭什么省/6-压缩为什么能省7倍空间.md' 2>&1 | head -5
echo
echo "=== 课 6 中是否含「伏笔」字样 ==="
grep -n '伏笔' 'stages/3-凭什么快凭什么省/6-压缩为什么能省7倍空间.md' 2>&1 | head -10
