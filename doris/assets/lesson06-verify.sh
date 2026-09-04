#!/bin/bash
BASE="/mnt/d/projects/learning/doris"
cd "$BASE" || exit 1

echo "=========================================="
echo "1. 链接可达性检查"
echo "=========================================="
TOTAL=0
BROKEN=0
while IFS= read -r f; do
  dir=$(dirname "$f")
  # 提取 markdown 链接目标
  grep -oP '\[[^\]]+\]\(\K[^)]+' "$f" 2>/dev/null | while IFS= read -r link; do
    case "$link" in
      http://*|https://*|'#'*) continue ;;
    esac
    clean="${link%%#*}"
    [ -z "$clean" ] && continue
    if [ -e "$dir/$clean" ]; then
      echo "  OK" > /dev/null
    else
      echo "  BROKEN [${f#$BASE/}] -> $clean"
    fi
  done
done < <(find . -name "*.md" -type f)

# 重新统计（上面的 subshell 计数丢失，改用简单扫描）
BROKEN_COUNT=0
LINK_COUNT=0
while IFS= read -r f; do
  dir=$(dirname "$f")
  links=$(grep -oP '\[[^\]]+\]\(\K[^)]+' "$f" 2>/dev/null)
  if [ -n "$links" ]; then
    while IFS= read -r link; do
      [ -z "$link" ] && continue
      case "$link" in
        http://*|https://*|'#'*) continue ;;
      esac
      clean="${link%%#*}"
      [ -z "$clean" ] && continue
      LINK_COUNT=$((LINK_COUNT+1))
      if [ ! -e "$dir/$clean" ]; then
        BROKEN_COUNT=$((BROKEN_COUNT+1))
        echo "  BROKEN [${f#$BASE/}] -> $clean"
      fi
    done <<< "$links"
  fi
done < <(find . -name "*.md" -type f)
echo "  链接总数: $LINK_COUNT, 失效: $BROKEN_COUNT"
if [ "$BROKEN_COUNT" -eq 0 ]; then echo "  LINK_CHECK_OK"; else echo "  LINK_CHECK_FAIL"; fi

echo ""
echo "=========================================="
echo "2. SVG 文件检查"
echo "=========================================="
BAD=0
while IFS= read -r s; do
  if grep -q "<svg" "$s" && grep -q "</svg>" "$s"; then
    echo "  OK: $(basename "$s")"
  else
    echo "  BAD: $(basename "$s")"
    BAD=$((BAD+1))
  fi
done < <(find . -name "*.svg" -type f)
if [ "$BAD" -eq 0 ]; then echo "  SVG_CHECK_OK"; else echo "  SVG_CHECK_FAIL"; fi

echo ""
echo "=========================================="
echo "3. 课 6 必备章节检查"
echo "=========================================="
L6="$BASE/stages/3-数据导入与查询/lessons/lesson-06-数据导入全家桶.md"
for sec in "第一幕：起源与场景引入" "第二幕：认知冲突" "第三幕：层层揭示" "第四幕：实操验证" "第五幕：体系收束" "常见误区" "一图总结" "课后小测" "下一批接力提示词" "课程导航"; do
  if grep -q "$sec" "$L6"; then echo "  OK: $sec"; else echo "  MISSING: $sec"; fi
done

echo ""
echo "=========================================="
echo "4. 四处档案回写检查"
echo "=========================================="
if grep -q "| 3 | 课 6 | Stream Load | ✅ 已完成 |" "$BASE/00-学习档案.md"; then echo "  OK: 学习档案进度表"; else echo "  MISS: 学习档案进度表"; fi
if grep -q "\[x\] 阶段 3·课 6" "$BASE/00-评审清单.md"; then echo "  OK: 评审清单已勾选"; else echo "  MISS: 评审清单"; fi
if grep -q "\[x\] \`lessons/lesson-06" "$BASE/stages/3-数据导入与查询/overview.md"; then echo "  OK: 阶段 overview"; else echo "  MISS: overview"; fi
if grep -q "18 / 36" "$BASE/01-学习路径总览.md"; then echo "  OK: 学习路径总览 18/36"; else echo "  MISS: 总览进度"; fi
if grep -q "lesson-06-数据导入全家桶.md)" "$BASE/02-课程目录.md"; then echo "  OK: 课程目录链接"; else echo "  MISS: 课程目录"; fi
