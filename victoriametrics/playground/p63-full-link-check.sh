cd /mnt/d/projects/learning/victoriametrics

PROBLEM=0
CHECKED=0
FILES=0

echo "=============== 全课程 Markdown 内部链接检查 ==============="
echo ""

# 遍历所有 md 文件（排除 node_modules / data 目录）
find . -name '*.md' -type f \
  -not -path './playground/data/*' \
  -not -path './playground/cluster-data/*' \
  -not -path '*/node_modules/*' \
  -print0 2>/dev/null | while IFS= read -r -d '' f; do

  dir=$(dirname "$f")
  FILES=$((FILES+1))

  # 抽取 markdown 链接目标，只保留本地相对路径（跳过 http / 锚点 / mailto）
  grep -oE '\]\(([^)]+)\)' "$f" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//' | while read -r target; do
    case "$target" in
      http://*|https://*|mailto:*|'#'*) continue ;;
    esac
    # 去掉 #锚点 与 ?查询
    clean=$(echo "$target" | sed -E 's/[#?].*$//')
    [ -z "$clean" ] && continue
    CHECKED=$((CHECKED+1))
    if [ ! -e "$dir/$clean" ]; then
      echo "  ❌ 断链：$f → $clean"
      PROBLEM=$((PROBLEM+1))
    fi
  done
done

echo ""
echo "=============== 关键锚点检查（跨文件引用编号） ==============="

echo "-- 08 引用 09 的症状编号是否都存在 --"
grep -oE '症状 ?[0-9]+' 08-实战经验.md | grep -oE '[0-9]+' | sort -un | while read -r n; do
  if grep -qE "^## .*症状 ?${n}[:：]" 09-排障速查手册.md; then
    echo "  ✅ 症状 $n"
  else
    echo "  ❌ 症状 $n 在 09 中不存在"
    PROBLEM=$((PROBLEM+1))
  fi
done

echo "-- 09 回指 08 的故障模式编号是否都存在 --"
grep -oE '故障模式 ?[0-9]+' 09-排障速查手册.md | grep -oE '[0-9]+' | sort -un | while read -r n; do
  if grep -qE "^### 故障模式 ?${n}" 08-实战经验.md; then
    echo "  ✅ 故障模式 $n"
  else
    echo "  ❌ 故障模式 $n 在 08 中不存在"
    PROBLEM=$((PROBLEM+1))
  fi
done

echo "-- 10 引用 08/09 的编号是否都存在 --"
grep -oE '故障模式 ?[0-9]+' 10-场景解法库.md | grep -oE '[0-9]+' | sort -un | while read -r n; do
  if grep -qE "^### 故障模式 ?${n}" 08-实战经验.md; then
    echo "  ✅ 10→08 故障模式 $n"
  else
    echo "  ❌ 10→08 故障模式 $n 不存在"
    PROBLEM=$((PROBLEM+1))
  fi
done
grep -oE '症状 ?[0-9]+' 10-场景解法库.md | grep -oE '[0-9]+' | sort -un | while read -r n; do
  if grep -qE "^## .*症状 ?${n}[:：]" 09-排障速查手册.md; then
    echo "  ✅ 10→09 症状 $n"
  else
    echo "  ❌ 10→09 症状 $n 不存在"
    PROBLEM=$((PROBLEM+1))
  fi
done

echo ""
echo "=============== 统计 ==============="
echo "  Markdown 文件数：$(find . -name '*.md' -type f -not -path './playground/data/*' -not -path './playground/cluster-data/*' | wc -l)"
echo "  本地链接总数：$(find . -name '*.md' -type f -not -path './playground/data/*' -not -path './playground/cluster-data/*' -print0 | xargs -0 grep -ohE '\]\(([^)]+)\)' 2>/dev/null | grep -vE 'http|mailto|^\)|#' | wc -l)"
echo "  问题数：$PROBLEM"
