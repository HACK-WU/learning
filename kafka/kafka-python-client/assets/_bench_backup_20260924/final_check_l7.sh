#!/bin/bash
# 课 7 交付后全库终检
set -u
K=/mnt/d/projects/learning/kafka/kafka-python-client

echo "=== 1. 全库围栏奇偶终检 ==="
bad=0
while IFS= read -r f; do
  n=$(awk '/^```/{c++} END{print c+0}' "$f")
  if [ $((n % 2)) -ne 0 ]; then
    echo "  ✗ 奇数围栏: $f ($n)"
    bad=$((bad + 1))
  fi
done < <(find "$K" -name '*.md' -type f)
echo "  奇数围栏文件数 = $bad （应为 0）"

echo ""
echo "=== 2. 课 7 断链终检 ==="
cd "$K/stages/3-生产层-吞吐与可靠性" || exit 1
broken=0
while IFS= read -r p; do
  if [ ! -e "$p" ]; then echo "  ✗ 断链: $p"; broken=$((broken + 1)); fi
done < <(grep -oE '\]\(\.\.?/[^)]+\)' 课7-吞吐调优与压缩.md \
         | sed 's/^](//; s/)$//' | sort -u)
echo "  断链数 = $broken （应为 0）"

echo ""
echo "=== 3. 索引回写确认（四处档案）==="
grep -q '课7-吞吐调优与压缩.md' "$K/02-课程目录.md" \
  && echo "  ✓ 02-课程目录.md 已链课 7" || echo "  ✗ 02-课程目录.md 缺课 7 链接"
grep -q '已完成 7 课' "$K/01-学习路径总览.md" \
  && echo "  ✓ 01-学习路径总览.md 进度已更新" || echo "  ✗ 路径总览进度未更新"
grep -q '课 7 吞吐调优与压缩' "$K/00-评审清单.md" \
  && echo "  ✓ 00-评审清单.md 已记课 7" || echo "  ✗ 评审清单缺课 7"
grep -q '✅ 已讲解' "$K/stages/3-生产层-吞吐与可靠性/overview.md" \
  && echo "  ✓ 阶段 3 overview 已标课 7 完成" || echo "  ✗ overview 未更新"
grep -q '✅ 已完成' "$K/00-学习档案.md" \
  && echo "  ✓ 00-学习档案.md 课 7 已标完成" || echo "  ✗ 学习档案未更新"

echo ""
echo "=== 4. 集群与容器卫生 ==="
bash "$K/assets/bench/check_hygiene.sh" 2>&1 | head -3
echo "  残留容器:"
docker ps -a --filter name=bench --format '    {{.Names}}' 2>/dev/null | head -3
docker ps -a --filter name=diag --format '    {{.Names}}' 2>/dev/null | head -3
docker ps -a --filter name=slow --format '    {{.Names}}' 2>/dev/null | head -3
echo "    (以上为空即无残留)"
