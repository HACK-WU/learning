#!/bin/bash
# 双视角评审支撑脚本：跨文件交叉引用与一致性核查
BASE=/mnt/d/projects/learning/victoriametrics
cd "$BASE" || exit 1

echo "===== A. 08 与 09 的编号交叉引用是否一一对应 ====="
echo "-- 08 中出现的「症状 N」引用 --"
grep -o '症状 [0-9]*' 08-实战经验.md | sort -u
echo "-- 09 中实际定义的症状编号 --"
grep -o '^## .*症状 [0-9]*' 09-排障速查手册.md | grep -o '症状 [0-9]*' | sort -u
echo "-- 09 中回指 08 的故障模式编号 --"
grep -o '故障模式 [0-9]*' 09-排障速查手册.md | sort -u

echo ""
echo "===== B. 10 中回指 08/09 的编号是否存在 ====="
grep -o '故障模式 [0-9]*' 10-场景解法库.md | sort -u
grep -o '症状 [0-9]*' 10-场景解法库.md | sort -u

echo ""
echo "===== C. 09 索引表条目数 vs 正文条目数 ====="
TOC=$(sed -n '/^## 🔎 症状倒查索引/,/^---/p' 09-排障速查手册.md | grep -c '^\|.*症状 [0-9]*|')
BODY=$(grep -c '^## .*症状 [0-9]*' 09-排障速查手册.md)
echo "索引表条目: $TOC   正文条目: $BODY"

echo ""
echo "===== D. 三份产物对同一坑的口径是否一致（抽查） ====="
for kw in 'labeldrop' 'absent(last_over_time' '7.4' '2,348' 'unauthorized_user' '10,580,035'; do
  c08=$(grep -cF "$kw" 08-实战经验.md)
  c09=$(grep -cF "$kw" 09-排障速查手册.md)
  c10=$(grep -cF "$kw" 10-场景解法库.md)
  cman=$(grep -cF "$kw" final-课程手册.md)
  echo "  「$kw」 → 08:$c08 09:$c09 10:$c10 手册:$cman"
done

echo ""
echo "===== E. 场景解法库硬要求核查 ====="
echo "-- 每场景是否有「先自己想」 --"
grep -c '🔒 先自己想' 10-场景解法库.md
echo "-- 每场景是否有「推荐路径」 --"
grep -c '### 推荐路径' 10-场景解法库.md
echo "-- 每场景是否有「知识点挂钩」 --"
grep -c '### 知识点挂钩' 10-场景解法库.md
echo "-- 每场景是否有「不适用」 --"
grep -c '什么情况下此方案不适用' 10-场景解法库.md
echo "-- 解法一览数量 --"
grep -c '### 解法一览' 10-场景解法库.md

echo ""
echo "===== F. 手册是否覆盖全部 12 课 ====="
for n in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if grep -q "^### 课 $n：" final-课程手册.md; then echo "  ✅ 课 $n"; else echo "  ❌ 课 $n 缺失"; fi
done
