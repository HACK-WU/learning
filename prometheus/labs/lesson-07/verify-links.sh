#!/usr/bin/env bash
# 全局链接可达性校验：扫描所有 md 文件内的相对链接
ROOT=/mnt/d/projects/learning/prometheus
BAD=0; OK=0
LIST=""

add(){ LIST="$LIST $1"; }

# 收集所有 .md 文件
while IFS= read -r f; do add "$f"; done < <(find "$ROOT" -name "*.md" -not -path "*/labs/*" -not -path "*/node_modules/*")

echo "待校验文件数 = $(echo $LIST | wc -w)"
echo

for f in $LIST; do
  dir=$(dirname "$f")
  # 提取 markdown 链接中的相对路径
  links=$(grep -oE '\]\([^)h][^)]*\)' "$f" 2>/dev/null | sed 's/^](//; s/)$//' | sed 's/#.*$//' | grep -E '\.(md|svg|png)$' || true)
  for lk in $links; do
    # 去掉锚点
    p="$dir/$lk"
    if [ -e "$p" ]; then
      OK=$((OK+1))
    else
      BAD=$((BAD+1))
      echo "  DEAD  ${f#$ROOT/}  ->  $lk"
    fi
  done
done

echo
echo "=== 汇总: 可达=$OK  死链=$BAD ==="

echo
echo "=== 重点复核：课 7 的所有出链 ==="
F7="$ROOT/stages/3-规模化与生态/lessons/lesson-07-远程读写与Agent模式.md"
D7=$(dirname "$F7")
grep -oE '\]\([^)]+\)' "$F7" | sed 's/^](//; s/)$//' | grep -v '^http' | sort -u | while read -r lk; do
  p="$D7/$lk"
  if [ -e "$p" ]; then echo "  OK   $lk"; else echo "  DEAD $lk"; fi
done

echo
echo "=== 重点复核：指向课 7 的入链 ==="
grep -rn "lesson-07" "$ROOT" --include="*.md" 2>/dev/null | grep -v "^$F7" | sed "s|$ROOT/||" | while IFS= read -r line; do
  echo "  $line"
done
