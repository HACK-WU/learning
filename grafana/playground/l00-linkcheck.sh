#!/usr/bin/env bash
# 链接可达性检查：扫 grafana/ 下所有 .md 的 ](相对路径) 链接，逐个 Test-Path 等效校验
# 用法：wsl bash grafana/playground/l00-linkcheck.sh
set -u
ROOT=/mnt/d/projects/learning/grafana
cd "$ROOT" || exit 1

DEAD=0
TOTAL=0

while IFS= read -r mdfile; do
  dir=$(dirname "$mdfile")
  # 抓取 ](xxx) 形式的链接，排除 http(s) 与 mailto 与纯锚点
  links=$(grep -oE '\]\(([^)]+)\)' "$mdfile" \
    | sed -E 's/^\]\(//; s/\)$//' \
    | grep -vE '^(https?:|mailto:|#)' || true)
  [ -z "$links" ] && continue
  while IFS= read -r link; do
    [ -z "$link" ] && continue
    # 去掉 #锚点 部分
    target="${link%%#*}"
    [ -z "$target" ] && continue
    TOTAL=$((TOTAL+1))
    full="$dir/$target"
    if [ ! -e "$full" ]; then
      echo "DEAD: ${mdfile#$ROOT/} -> $link"
      DEAD=$((DEAD+1))
    fi
  done <<< "$links"
done < <(find "$ROOT" -name '*.md' -type f)

echo "-----------------------------------------"
echo "共检查链接 $TOTAL 条，死链 $DEAD 条"
[ "$DEAD" -eq 0 ] && echo "RESULT: OK" || echo "RESULT: FAIL"

echo "=== SVG 资产清单 ==="
find "$ROOT" -name '*.svg' -type f | sed "s#$ROOT/##"
