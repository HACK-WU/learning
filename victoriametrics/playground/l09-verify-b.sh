#!/bin/bash
# 核验 Agent B 的两条问题
F='/mnt/d/projects/learning/victoriametrics/stages/4-怎么横向扩展/9-复制去重与高可用.md'

echo "=== 核验 P1：副本缺口不修复 是否真缺失 ==="
echo "-- 误区区里含『补齐』的行 --"
awk '/## 🐞 常见误区/,/## 🚀/' "$F" | grep -n '补齐\|补副本\|不补' | head -6
echo
echo "-- 误区第 5 条完整内容 --"
awk '/### 5\. 以为节点恢复后副本会自动补齐/,/### 6\./' "$F" | head -14

echo
echo "=== 核验 P2：shared-nothing 是否有解释 ==="
echo "-- 含 shared-nothing 的行及上下文 --"
grep -n 'shared-nothing' "$F"
echo
echo "-- 检查『互不通信』是否出现 --"
grep -c '互不通信' "$F"
