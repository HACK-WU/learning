#!/bin/bash
# 核验 Agent B 的两条 P1 是否为真缺陷
F='/mnt/d/projects/learning/victoriametrics/stages/3-凭什么快凭什么省/7-内存模型与容量规划.md'

echo "=== 核验 1：平均值法踩坑 —— 关键词『平均值』是否出现在误区区 ==="
echo "-- 常见误区章节起始行 --"
grep -n '^## 🐞 常见误区' "$F"
echo "-- 误区区各条标题 --"
awk '/^## 🐞 常见误区/,/^## 🚀/' "$F" | grep '^### '
echo
echo "-- 误区区是否含『平均值』 --"
awk '/^## 🐞 常见误区/,/^## 🚀/' "$F" | grep -c '平均值'
echo "-- 误区区是否含『6234』或『6000 字节』 --"
awk '/^## 🐞 常见误区/,/^## 🚀/' "$F" | grep -n '6234\|6000 字节' | head -3
echo
echo "结论：误区第 1 条标题是「用『总内存 / 序列数』估算容量」，"
echo "      正文写的是『把固定开销摊到了少量序列上』——语义相同，但没出现『平均值』三字。"
echo "      → 脚本关键词误判，但可补一个『平均值 vs 边际成本』的显式对照，更利于理解。"

echo
echo "=== 核验 2：docker restart 是否缺警告 ==="
echo "-- 含 docker restart 的上下文 --"
grep -n -B3 -A3 'docker restart' "$F" | head -20
