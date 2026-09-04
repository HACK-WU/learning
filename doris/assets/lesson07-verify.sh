#!/bin/bash
# 课 7 交付校验：链接可达性 + SVG 完整性 + 必备章节 + 四处档案回写
LESSON=/mnt/d/projects/learning/doris/stages/3-数据导入与查询/lessons/lesson-07-查询引擎与执行计划.md
ASSETS=/mnt/d/projects/learning/doris/stages/3-数据导入与查询/assets
ROOT=/mnt/d/projects/learning/doris
FAIL=0

echo "########## 1. 必备章节检查 ##########"
CHAPTERS=("## 🎯 本课目标" "## 第一幕" "## 第二幕" "## 第三幕" "## 第四幕" "## 第五幕" "## 🐞 常见误区" "## 一图总结" "## ⚡ 速览模式" "## 🎓 课后小测" "## 🚀 下一批接力提示词" "## 🧭 课程导航")
for c in "${CHAPTERS[@]}"; do
  if grep -qF "$c" "$LESSON"; then
    echo "  [OK] $c"
  else
    echo "  [FAIL] 缺失章节: $c"
    FAIL=1
  fi
done

echo ""
echo "########## 2. 三个知识点检查 ##########"
KPS=("### 知识点 1：MPP 执行流程" "### 知识点 2：向量化执行与列存" "### 知识点 3：EXPLAIN 与 Profile")
for k in "${KPS[@]}"; do
  if grep -qF "$k" "$LESSON"; then echo "  [OK] $k"; else echo "  [FAIL] 缺失: $k"; FAIL=1; fi
done

echo ""
echo "########## 3. 文件内相对链接可达性 ##########"
LESSON_DIR=$(dirname "$LESSON")
grep -oE '\]\(([^)#]+\.md)\)' "$LESSON" | sed -e 's/](\(.*\))/\1/' | sort -u > /tmp/l7_links.txt
while read -r link; do
  [ -z "$link" ] && continue
  target="$LESSON_DIR/$link"
  if [ -f "$target" ]; then
    echo "  [OK] $link"
  else
    echo "  [FAIL] 链接不可达: $link -> $target"
    FAIL=1
  fi
done

echo ""
echo "########## 4. SVG 资产检查 ##########"
for svg in lesson-07-summary.svg lesson-07-columnar.svg; do
  if [ -f "$ASSETS/$svg" ]; then
    SIZE=$(wc -c < "$ASSETS/$svg")
    # 检查 SVG 首尾标签完整
    if head -1 "$ASSETS/$svg" | grep -q '<?xml\|<svg' && grep -q '</svg>' "$ASSETS/$svg"; then
      echo "  [OK] $svg (${SIZE} bytes, 标签完整)"
    else
      echo "  [FAIL] $svg 标签不完整"
      FAIL=1
    fi
  else
    echo "  [FAIL] 缺失 SVG: $svg"
    FAIL=1
  fi
done

echo ""
echo "########## 5. 正文引用的 SVG 是否都存在 ##########"
grep -oE '\]\(\.\./assets/[^)]+\.svg\)' "$LESSON" | sed -e 's/](\(.*\))/\1/' | sort -u > /tmp/l7_svgs.txt
while read -r link; do
  [ -z "$link" ] && continue
  target="$LESSON_DIR/$link"
  if [ -f "$target" ]; then echo "  [OK] $link"; else echo "  [FAIL] $link"; FAIL=1; fi
done < /tmp/l7_svgs.txt

echo ""
echo "########## 6. 实验脚本检查（第四幕引用的都要存在）##########"
for sh in lesson07-setup.sh lesson07-step2.sh lesson07-step3.sh lesson07-step4.sh lesson07-step5.sh lesson07-step6.sh lesson07-step7.sh lesson07-cleanup.sh; do
  if [ -f "/mnt/d/projects/learning/doris/assets/$sh" ]; then
    echo "  [OK] assets/$sh"
  else
    echo "  [FAIL] 缺失脚本: assets/$sh"
    FAIL=1
  fi
done

echo ""
echo "########## 7. 危险链接检查（/D:/ 开头的错误路径）##########"
BAD=$(grep -c '](/D:/' "$LESSON" 2>/dev/null)
BAD=${BAD:-0}
if [ "$BAD" -gt 0 ]; then
  echo "  [FAIL] 发现 $BAD 处 /D:/ 开头的错误链接"
  grep -n '](/D:/' "$LESSON" | head -5
  FAIL=1
else
  echo "  [OK] 无 /D:/ 错误链接"
fi

echo ""
echo "########## 8. 四处档案回写检查 ##########"
echo "--- 8.1 00-学习档案.md 课 7 三行是否已完成 ---"
for kp in "MPP 执行流程" "向量化执行与列存" "EXPLAIN 与 Profile"; do
  if grep -q "课 7.*$kp.*✅ 已完成" "$ROOT/00-学习档案.md"; then
    echo "  [OK] $kp"
  else
    echo "  [FAIL] 未完成: $kp"
    FAIL=1
  fi
done
echo "--- 8.2 00-评审清单.md 课 7 是否勾选 ---"
if grep -q '^\- \[x\] 阶段 3·课 7' "$ROOT/00-评审清单.md"; then
  echo "  [OK] 课 7 已勾选"
else
  echo "  [FAIL] 课 7 未勾选"
  FAIL=1
fi
echo "--- 8.3 overview.md 课 7 产出是否勾选 ---"
if grep -q '\[x\] `lessons/lesson-07-查询引擎与执行计划.md`' "$ROOT/stages/3-数据导入与查询/overview.md"; then
  echo "  [OK] overview 已勾选"
else
  echo "  [FAIL] overview 未勾选"
  FAIL=1
fi
echo "--- 8.4 02-课程目录.md 是否含课 7 链接 ---"
if grep -q 'lesson-07-查询引擎与执行计划.md' "$ROOT/02-课程目录.md"; then
  echo "  [OK] 课程目录已更新"
else
  echo "  [FAIL] 课程目录未更新"
  FAIL=1
fi
echo "--- 8.5 01-学习路径总览.md 进度是否 21/36 ---"
# 总览里实际写作「21 / 36」（数字与斜杠间带空格），用 -E 容错匹配，避免格式微调就误报 FAIL
if grep -qE '21 */ *36' "$ROOT/01-学习路径总览.md"; then
  echo "  [OK] 总览进度已更新为 21/36"
else
  echo "  [FAIL] 总览进度未更新"
  FAIL=1
fi

echo ""
if [ $FAIL -eq 0 ]; then
  echo "==================== VERIFY_OK ===================="
else
  echo "==================== VERIFY_FAILED ===================="
fi
