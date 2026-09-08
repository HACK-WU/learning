#!/usr/bin/env bash
ROOT=/d/projects/learning/prometheus
BAD=0; OK=0
echo "=== 全仓 Markdown 本地链接可达性检查 ==="
while IFS= read -r f; do
  d=$(dirname "$f")
  while IFS= read -r L; do
    tgt="${L%%#*}"
    [ -z "$tgt" ] && continue
    case "$tgt" in http://*|https://*|mailto:*) continue;; esac
    if [ -e "$d/$tgt" ]; then OK=$((OK+1)); else
      echo "BROKEN: $f -> $tgt"
      BAD=$((BAD+1))
    fi
  done < <(grep -oP '(?<=\]\()[^)]+' "$f" 2>/dev/null)
done < <(find "$ROOT" -name '*.md' -not -path '*/node_modules/*')
echo "----------------------------------------"
echo "可达: $OK   断链: $BAD"
