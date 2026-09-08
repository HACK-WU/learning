#!/usr/bin/env bash
set -uo pipefail
ROOT=/mnt/d/projects/learning/prometheus

echo "=== 1. 死链都来自哪些文件？==="
cut -d'|' -f2 /tmp/deadlinks.txt | sort | uniq -c | sort -rn

echo
echo "=== 2. 正式讲义（stages/**/lessons/*.md）是否有死链？==="
n=0
while read -r line; do
  f=$(echo "$line" | cut -d'|' -f2)
  case "$f" in
    */stages/*/lessons/*) echo "  正式讲义死链: $line"; n=$((n+1));;
  esac
done < /tmp/deadlinks.txt
[ "$n" -eq 0 ] && echo "  ✅ 正式讲义 0 死链" || echo "  ❌ 正式讲义 $n 条死链"

echo
echo "=== 3. 课 9 正式讲义单独校验 ==="
L=$ROOT/stages/3-规模化与生态/lessons/lesson-09-长期存储选型.md
d=$(dirname "$L")
cnt=0; dead=0
grep -oE '\]\(\.\.?[^)#]+\.md\)' "$L" | sed 's/^](//; s/)$//' | sort -u | while read -r rel; do
  if [ -f "$d/$rel" ]; then echo "  OK   $rel"; else echo "  MISS $rel"; fi
done

echo
echo "=== 4. 其他档案文件（00-*.md / 01-*.md / 02-*.md / overview.md）==="
for f in "$ROOT/00-学习档案.md" "$ROOT/00-评审清单.md" "$ROOT/01-学习路径总览.md" \
         "$ROOT/02-课程目录.md" "$ROOT/stages/3-规模化与生态/overview.md"; do
  d=$(dirname "$f")
  bad=0
  while read -r rel; do
    [ -f "$d/$rel" ] || { echo "  MISS $(basename "$f") -> $rel"; bad=1; }
  done < <(grep -oE '\]\(\.\.?[^)#]+\.md\)' "$f" | sed 's/^](//; s/)$//' | sort -u)
  [ "$bad" -eq 0 ] && echo "  OK   $(basename "$f")"
done
