#!/bin/bash
# 课 8 交付校验：章节完整性 + 链接可达性 + SVG + 脚本存在性 + 四处档案回写
LESSON=/mnt/d/projects/learning/doris/stages/3-数据导入与查询/lessons/lesson-08-多表关联与高级SQL.md
ASSETS=/mnt/d/projects/learning/doris/stages/3-数据导入与查询/assets
ROOT=/mnt/d/projects/learning/doris
FAIL=0
say() { echo "$1"; }

echo "########## 1. 必备章节检查 ##########"
CHAPTERS=("## 🎯 本课目标" "## 第一幕" "## 第二幕" "## 第三幕" "## 第四幕" "## 第五幕" "## 🐞 常见误区" "## 一图总结" "## ⚡ 速览模式" "## 🎓 课后小测" "## 🚀 下一批接力提示词" "## 🧭 课程导航")
for c in "${CHAPTERS[@]}"; do
  if grep -qF "$c" "$LESSON"; then say "  [OK] $c"; else say "  [FAIL] 缺失章节: $c"; FAIL=1; fi
done

echo ""
echo "########## 2. 三个知识点检查 ##########"
KPS=("### 知识点 1：Join 与分布式 Join 策略" "### 知识点 2：复杂类型与半结构化数据" "### 知识点 3：异步物化视图与查询改写")
for k in "${KPS[@]}"; do
  if grep -qF "$k" "$LESSON"; then say "  [OK] $k"; else say "  [FAIL] 缺失: $k"; FAIL=1; fi
done

echo ""
echo "########## 3. 骨架要求的易混提示是否保留 ##########"
if grep -qF "异步物化视图（本课）≠ 同步 Rollup（课 5）" "$LESSON"; then
  say "  [OK] 易混提示（大纲评审 P1-1）已保留"
else
  say "  [FAIL] 骨架要求的易混提示丢失"; FAIL=1
fi

echo ""
echo "########## 4. 文件内相对链接可达性 ##########"
LESSON_DIR=$(dirname "$LESSON")
grep -oE '\]\(([^)#]+\.md)\)' "$LESSON" | sed -e 's/](\(.*\))/\1/' | sort -u > /tmp/l8_links.txt
while read -r link; do
  [ -z "$link" ] && continue
  target="$LESSON_DIR/$link"
  if [ -f "$target" ]; then say "  [OK] $link"; else say "  [FAIL] 链接不可达: $link -> $target"; FAIL=1; fi
done < /tmp/l8_links.txt

echo ""
echo "########## 5. SVG 资产检查 ##########"
for svg in lesson-08-summary.svg lesson-08-join.svg; do
  if [ -f "$ASSETS/$svg" ]; then
    SIZE=$(wc -c < "$ASSETS/$svg")
    if head -1 "$ASSETS/$svg" | grep -q '<?xml\|<svg' && grep -q '</svg>' "$ASSETS/$svg"; then
      say "  [OK] $svg (${SIZE} bytes, 标签完整)"
    else
      say "  [FAIL] $svg 标签不完整"; FAIL=1
    fi
  else
    say "  [FAIL] 缺失 SVG: $svg"; FAIL=1
  fi
done

echo ""
echo "########## 6. 正文引用的 SVG 是否都存在 ##########"
grep -oE '\]\(\.\./assets/[^)]+\.svg\)' "$LESSON" | sed -e 's/](\(.*\))/\1/' | sort -u > /tmp/l8_svgs.txt
while read -r link; do
  [ -z "$link" ] && continue
  target="$LESSON_DIR/$link"
  if [ -f "$target" ]; then say "  [OK] $link"; else say "  [FAIL] $link"; FAIL=1; fi
done < /tmp/l8_svgs.txt

echo ""
echo "########## 7. 实验脚本检查（第四幕引用的都要存在）##########"
for sh in lesson08-setup.sh lesson08-step2.sh lesson08-step3.sh lesson08-step4.sh lesson08-step5.sh lesson08-step6.sh lesson08-step7.sh lesson08-cleanup.sh; do
  if [ -f "/mnt/d/projects/learning/doris/assets/$sh" ]; then
    say "  [OK] assets/$sh"
  else
    say "  [FAIL] 缺失脚本: assets/$sh"; FAIL=1
  fi
done

echo ""
echo "########## 8. 危险链接检查（/D:/ 开头的错误路径）##########"
BAD=$(grep -c '](/D:/' "$LESSON" 2>/dev/null)
BAD=${BAD:-0}
if [ "$BAD" -gt 0 ]; then
  say "  [FAIL] 发现 $BAD 处 /D:/ 开头的错误链接"
  grep -n '](/D:/' "$LESSON" | head -5
  FAIL=1
else
  say "  [OK] 无 /D:/ 错误链接"
fi

echo ""
echo "########## 9. 脚本是否都带 docker exec -i（前几课 P0 陷阱）##########"
NO_I=0
for sh in lesson08-setup.sh lesson08-step2.sh lesson08-step3.sh lesson08-step4.sh lesson08-step5.sh lesson08-step6.sh lesson08-step7.sh lesson08-cleanup.sh; do
  P="/mnt/d/projects/learning/doris/assets/$sh"
  # 脚本里若有 docker exec 但没带 -i，就是隐患
  if grep -q 'docker exec' "$P" && ! grep -qE 'docker exec -i|docker exec +-i' "$P"; then
    say "  [FAIL] $sh 里 docker exec 缺 -i"
    NO_I=1
  fi
done
if [ $NO_I -eq 0 ]; then say "  [OK] 所有脚本的 docker exec 都带 -i"; else FAIL=1; fi

echo ""
echo "########## 10. 四处档案回写检查 ##########"
echo "--- 10.1 00-学习档案.md 课 8 三行是否已完成 ---"
for kp in "Join 与分布式 Join 策略" "复杂类型与半结构化数据" "异步物化视图与查询改写"; do
  if grep -q "课 8.*$kp.*✅ 已完成" "$ROOT/00-学习档案.md"; then
    say "  [OK] $kp"
  else
    say "  [FAIL] 未完成: $kp"; FAIL=1
  fi
done
echo "--- 10.2 00-评审清单.md 课 8 是否勾选 ---"
if grep -q '^\- \[x\] 阶段 3·课 8' "$ROOT/00-评审清单.md"; then
  say "  [OK] 课 8 已勾选"
else
  say "  [FAIL] 课 8 未勾选"; FAIL=1
fi
echo "--- 10.3 overview.md 课 8 产出是否勾选 ---"
if grep -q '\[x\] `lessons/lesson-08-多表关联与高级SQL.md`' "$ROOT/stages/3-数据导入与查询/overview.md"; then
  say "  [OK] overview 已勾选"
else
  say "  [FAIL] overview 未勾选"; FAIL=1
fi
echo "--- 10.4 02-课程目录.md 是否含课 8 链接 ---"
if grep -q 'lesson-08-多表关联与高级SQL.md' "$ROOT/02-课程目录.md"; then
  say "  [OK] 课程目录已更新"
else
  say "  [FAIL] 课程目录未更新"; FAIL=1
fi
echo "--- 10.5 01-学习路径总览.md 进度是否 24/36 ---"
if grep -qE '24 */ *36' "$ROOT/01-学习路径总览.md"; then
  say "  [OK] 总览进度已更新为 24/36"
else
  say "  [FAIL] 总览进度未更新"; FAIL=1
fi

echo ""
if [ $FAIL -eq 0 ]; then
  echo "==================== VERIFY_OK ===================="
else
  echo "==================== VERIFY_FAILED ===================="
fi
