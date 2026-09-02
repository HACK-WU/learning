#!/bin/bash
# Phase 4 汇总完整性 + 双视角评审核查
set -u
cd /mnt/d/projects/learning/redis
F=final-课程手册.md

echo "===== 1. 九课是否全部纳入 ====="
for n in 01 02 03 04 05 06 07 08 09; do
  if grep -q "课 ${n#0}：" "$F"; then echo "  OK   课 ${n#0} 已纳入"; else echo "  MISS 课 ${n#0} 未纳入"; fi
done

echo
echo "===== 2. 四阶段是否全部纳入 ====="
for s in 1 2 3 4; do
  if grep -q "^# 阶段 ${s}：" "$F"; then echo "  OK   阶段 ${s} 已纳入"; else echo "  MISS 阶段 ${s} 未纳入"; fi
done

echo
echo "===== 3. 一图总结保留数（课 1/2/3 有 mermaid，课 4 有决策树）====="
echo "  mermaid 代码块: $(grep -c '```mermaid' "$F")"
echo "  纯文本决策树/代码块: $(grep -c '^```$' "$F")"

echo
echo "===== 4. 实战项目是否收录 ====="
grep -q "^# 综合实战项目" "$F" && echo "  OK   已收录" || echo "  MISS 未收录"
grep -q "设计决策摘要" "$F" && echo "  OK   决策摘要已收录" || echo "  MISS 决策摘要缺失"
grep -q "覆盖知识点地图" "$F" && echo "  OK   知识点地图已收录" || echo "  MISS 知识点地图缺失"

echo
echo "===== 5. 学习目标附加内容（四项全要 → 考点速记 + 决策清单）====="
grep -q "^# 考点速记" "$F" && echo "  OK   考点速记已收录" || echo "  MISS 考点速记缺失"
grep -q "^# 决策清单" "$F" && echo "  OK   决策清单已收录" || echo "  MISS 决策清单缺失"

echo
echo "===== 6. 手册内所有相对链接目标是否真实存在 ====="
grep -oP '\]\(\K[^)#][^)]*' "$F" | sort -u | while read -r l; do
  case "$l" in
    http*) continue ;;
    \#*) continue ;;
  esac
  if [ -e "$l" ]; then echo "  OK   $l"; else echo "  MISS $l"; fi
done

echo
echo "===== 7. 关键数字一致性抽查（应与课时原文一致）====="
for pair in "9.6%" "21.7%" "16384" "0.81%" "12 KB" "5934x" "113.66" "0.61" "185.7" "1999" "189" "6.87" "1.00x" "43 倍" "7.06" "531 倍"; do
  if grep -q "$pair" "$F"; then echo "  OK   $pair"; else echo "  MISS $pair"; fi
done

echo
echo "===== 8. 手册规模 ====="
echo "  行数: $(wc -l < "$F")  字节: $(wc -c < "$F")"
