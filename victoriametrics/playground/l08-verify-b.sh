#!/bin/bash
# 核验 Agent B 的两条 P2
F='/mnt/d/projects/learning/victoriametrics/stages/4-怎么横向扩展/8-集群三件套与最小集群实战.md'

echo "=== 核验 L9：选型清单是否真缺信号 ==="
echo "-- 决策清单实际内容 --"
awk '/### 什么时候该上集群/,/^### 你现在会了什么/' "$F" | head -30

echo
echo "=== 核验 L8：docker stop 的上下文 ==="
grep -n 'docker stop' "$F" | head -5
echo "-- 第一次出现的上下文 --"
N=$(grep -n 'docker stop' "$F" | head -1 | cut -d: -f1)
sed -n "$((N-6)),$((N+4))p" "$F"
