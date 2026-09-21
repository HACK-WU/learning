#!/usr/bin/env bash
# 双视角评审的事实核验：逐条回读讲义 + 对照实测
M="/mnt/d/projects/learning/consul/子教程/运维专项/lessons/lesson-01-生产部署与集群搭建.md"

echo "===== 1. 结构完整性（五幕 + 速查卡 + 导航）====="
for s in '## 第一幕' '## 第二幕' '## 第三幕' '## 第四幕' '## 第五幕' '## 📇 概念速查卡' '## 🚀 下一批接力提示词' '## 🧭 课程导航'; do
  c=$(grep -c "^$s" "$M"); printf "  %-28s %s\n" "$s" "$([ "$c" -ge 1 ] && echo OK || echo MISSING)"
done

echo
echo "===== 2. 三个知识点齐备 ====="
grep -n '^### 知识点' "$M"

echo
echo "===== 3. 图片引用 ====="
grep -n '!\[' "$M"

echo
echo "===== 4. 相对链接清单 ====="
grep -oE '\]\(\.\.?[^)]+\)' "$M" | tr -d '[]()' | sort -u
