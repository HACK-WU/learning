#!/bin/bash
# 读取课 8 的多租户部分，确认课 10 的起点与边界
F='/mnt/d/projects/learning/victoriametrics/stages/4-怎么横向扩展/8-集群三件套与最小集群实战.md'

echo "=== 课 8 中『多租户』相关章节 ==="
grep -n '租户\|tenant\|accountID\|projectID\|多租户' "$F" | head -40

echo
echo "=== 课 8 知识点 5 完整内容 ==="
awk '/知识点 5：多租户隔离/,/^## 第四幕/' "$F" | head -80
