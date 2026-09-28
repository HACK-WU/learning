#!/usr/bin/env bash
cd /mnt/d/projects/learning/bk-blueking-72 || exit 1

echo "===== 1. 文档内引用的本地链接是否可达 ====="
for f in 08-实战经验.md 09-排障速查手册.md 00-学习档案.md 00-评审清单.md 02-课程目录.md stages/2-存储层攻坚/overview.md; do
  d=$(dirname "$f")
  grep -oE '\]\([^)h][^)]*\)' "$f" 2>/dev/null | sed 's/^](//; s/)$//' | while read -r link; do
    # 去掉锚点
    l="${link%%#*}"
    [ -z "$l" ] && continue
    if [ -e "$d/$l" ]; then
      echo "  OK   $f -> $l"
    elif [ -e "$l" ]; then
      echo "  OK   $f -> $l (相对根)"
    else
      echo "  MISS $f -> $l"
    fi
  done
done

echo ""
echo "===== 2. 数字一致性：08 与 09 与档案是否打架 ====="
echo "  [Pod 数]"
grep -ohE '(131|128) 个? ?Pod|Pod *131|[0-9]+ / 12' 08-实战经验.md 09-排障速查手册.md 00-学习档案.md 2>/dev/null | sort | uniq -c
echo "  [PVC]"
grep -ohE '1[14] */ *1[14] *(PVC|Bound)|PVC *1[14]' 08-实战经验.md 00-学习档案.md stages/2-存储层攻坚/overview.md 2>/dev/null | sort | uniq -c
echo "  [user 数]"
grep -ohE 'user( count)?[ =:]*0*[25]|user 0→5|user=5' 08-实战经验.md 09-排障速查手册.md 00-学习档案.md 2>/dev/null | sort | uniq -c
echo "  [内存峰值]"
grep -ohE '(37%|29%|4%|5%)' 08-实战经验.md 00-学习档案.md 2>/dev/null | sort | uniq -c

echo ""
echo "===== 3. 索引是否都写到了 ====="
for kw in "08-实战经验" "09-排障速查手册"; do
  for idx in 02-课程目录.md 00-学习档案.md 00-评审清单.md; do
    if grep -q "$kw" "$idx"; then echo "  OK   $idx 含 $kw"; else echo "  MISS $idx 缺 $kw"; fi
  done
done
