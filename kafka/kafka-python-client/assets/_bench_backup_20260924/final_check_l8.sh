#!/bin/bash
# 课 8 交付后全库终检
set -u
K=/mnt/d/projects/learning/kafka/kafka-python-client
L8="$K/stages/3-生产层-吞吐与可靠性/课8-事务与恰好一次.md"

echo "=== 1. 全库围栏奇偶终检 ==="
bad=0
while IFS= read -r f; do
  n=$(awk '/^```/{c++} END{print c+0}' "$f")
  [ $((n % 2)) -ne 0 ] && { echo "  ✗ 奇数围栏: $f ($n)"; bad=$((bad+1)); }
done < <(find "$K" -name '*.md' -type f)
echo "  奇数围栏文件数 = $bad（应为 0）"

echo ""
echo "=== 2. 课 8 断链终检 ==="
cd "$K/stages/3-生产层-吞吐与可靠性" || exit 1
b=0
while IFS= read -r p; do
  [ ! -e "$p" ] && { echo "  ✗ 断链: $p"; b=$((b+1)); }
done < <(grep -oE '\]\(\.\.?/[^)]+\)' 课8-事务与恰好一次.md \
         | sed 's/^](//; s/)$//' | sort -u)
echo "  断链数 = $b（应为 0）"

echo ""
echo "=== 3. 四处档案回写确认 ==="
grep -q '课8-事务与恰好一次.md' "$K/02-课程目录.md" \
  && echo "  ✓ 02-课程目录.md 已链课 8" || echo "  ✗ 目录缺课 8 链接"
grep -q '已完成 8 课' "$K/01-学习路径总览.md" \
  && echo "  ✓ 01-学习路径总览.md 进度已更新" || echo "  ✗ 路径总览未更新"
grep -q '课 8 事务与恰好一次' "$K/00-评审清单.md" \
  && echo "  ✓ 00-评审清单.md 已记课 8" || echo "  ✗ 评审清单缺课 8"
grep -q '课 8 | 事务 API 与 EOS 语义 | ✅ 已完成' "$K/00-学习档案.md" \
  && echo "  ✓ 00-学习档案.md 课 8 已标完成" || echo "  ✗ 学习档案未更新"
grep -q '✅ 已讲解（2026-09-21）' "$K/stages/3-生产层-吞吐与可靠性/overview.md" \
  && echo "  ✓ 阶段 3 overview 已标课 8 完成" || echo "  ✗ overview 未更新"

echo ""
echo "=== 4. 实测资产脚本存在性（正文引用 7 个）==="
for s in probe_txn_api probe_kp_txn_real probe_eos_e2e probe_fencing \
         probe_txn_cost probe_txn_cost_one probe_kp_txn_state; do
  f="$K/assets/bench/$s.sh"
  [ -f "$f" ] && echo "  ✓ $s.sh" || echo "  ✗ 缺失 $s.sh"
done

echo ""
echo "=== 5. 集群卫生 ==="
bash "$K/assets/bench/check_hygiene.sh" 2>&1 | head -3
