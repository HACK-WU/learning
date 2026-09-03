#!/bin/bash
# Phase 4 + Phase 5 交付检查：
#  1. 四份产物存在性与行数
#  2. 内部链接可达性（含锚点所在文件存在）
#  3. 结构合规（必备区块）
#  4. 数字一致性（与讲义/档案中的实测数字比对）
BASE=/mnt/d/projects/learning/victoriametrics
PROBLEM=0

echo "=============== 1. 产物存在性 ==============="
for f in final-课程手册.md 08-实战经验.md 09-排障速查手册.md 10-场景解法库.md; do
  if [ -f "$BASE/$f" ]; then
    echo "  ✅ $f ($(wc -l < "$BASE/$f") 行)"
  else
    echo "  ❌ $f 缺失"; PROBLEM=$((PROBLEM+1))
  fi
done

echo ""
echo "=============== 2. 内部链接可达性 ==============="
cd "$BASE" || exit 1
for f in final-课程手册.md 08-实战经验.md 09-排障速查手册.md 10-场景解法库.md; do
  LINKS=$(grep -o '](\([^)]*\))' "$f" | sed 's/](//; s/)$//' | grep -v '^http' | grep -v '^#' | sort -u)
  for L in $LINKS; do
    target="${L%%#*}"
    if [ -z "$target" ]; then echo "  - $f: 页内锚点 $L"; continue; fi
    if [ -e "$target" ]; then
      echo "  ✅ $f → $target"
    else
      echo "  ❌ $f → $target 不可达"; PROBLEM=$((PROBLEM+1))
    fi
  done
done

echo ""
echo "=============== 3. 结构合规 ==============="
check_sec() {
  if grep -q "$2" "$BASE/$1"; then echo "  ✅ $1 含「$2」"; else echo "  ❌ $1 缺「$2」"; PROBLEM=$((PROBLEM+1)); fi
}
check_sec "final-课程手册.md" "## 综合实战项目"
check_sec "final-课程手册.md" "## 决策清单"
check_sec "final-课程手册.md" "## 故事主线"
check_sec "final-课程手册.md" "## 全局速查"
check_sec "08-实战经验.md" "## 🚫 适用边界与反模式"
check_sec "08-实战经验.md" "## ✅ 落地 / 上线 Checklist"
check_sec "09-排障速查手册.md" "## 🔎 症状倒查索引"
check_sec "10-场景解法库.md" "## 🗂️ 场景索引"

echo ""
echo "=============== 4. 数字一致性抽查 ==============="
# 每个数字：文件 -> 期望出现
declare -a CHECKS=(
  "final-课程手册.md|5.583"
  "final-课程手册.md|65.5"
  "final-课程手册.md|2,548"
  "final-课程手册.md|139.8"
  "08-实战经验.md|139.8"
  "08-实战经验.md|2,348"
  "08-实战经验.md|7.4"
  "09-排障速查手册.md|1,068"
  "09-排障速查手册.md|4.37"
  "10-场景解法库.md|10,580,035"
)
for c in "${CHECKS[@]}"; do
  f="${c%%|*}"; n="${c##*|}"
  if grep -qF "$n" "$BASE/$f"; then echo "  ✅ $f 含 $n"; else echo "  ❌ $f 缺 $n"; PROBLEM=$((PROBLEM+1)); fi
done

echo ""
echo "=============== 5. 场景/故障模式计数 ==============="
echo "  08 故障模式数：$(grep -c '^### 故障模式' "$BASE/08-实战经验.md")"
echo "  09 症状条目数：$(grep -c '^## .*症状' "$BASE/09-排障速查手册.md")"
echo "  10 场景数：$(grep -c '^## 场景 ' "$BASE/10-场景解法库.md")"
echo "  10 折叠块数：$(grep -c 'details>' "$BASE/10-场景解法库.md")"

echo ""
echo "=============== 汇总 ==============="
echo "问题数：$PROBLEM"
