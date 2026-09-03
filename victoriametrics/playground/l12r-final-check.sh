#!/bin/bash
echo "======================================================================"
echo "课 12 补充实验（三项遗留闭环）交付校验"
echo "======================================================================"
cd /mnt/d/projects/learning/victoriametrics

echo ""
echo "[1] 讲义文件"
L12="stages/5-生产落地/12-备份恢复迁移与选型决策.md"
printf "  行数: %s  字符: %s  字节: %s\n" \
  "$(wc -l < "$L12")" "$(wc -m < "$L12")" "$(wc -c < "$L12")"

echo ""
echo "[2] 三项遗留闭环标记"
grep -c "补论" "$L12" | xargs -I{} echo "  补论章节数: {}"
grep -o "#### 补论：[^（]*" "$L12" | sed 's/^/  ✅ /'

echo ""
echo "[3] 误区数量"
printf "  编号误区: %s 条\n" "$(grep -cE '^\*\*误区 [0-9]+：' "$L12")"
printf "  汇总清单: %s 条\n" "$(sed -n '/### 🐞 常见误区汇总/,/### 决策清单/p' "$L12" | grep -cE '^[0-9]+\. ')"

echo ""
echo "[4] 实验清单"
printf "  实验条目: %s 条\n" "$(sed -n '/### 实验清单/,/### 实验 14 详解/p' "$L12" | grep -cE '^\| [0-9]+ \|')"

echo ""
echo "[5] 决策清单勾选率"
total=$(sed -n '/### 决策清单/,/^---/p' "$L12" | grep -cE '^- \[')
done_n=$(sed -n '/### 决策清单/,/^---/p' "$L12" | grep -cE '^- \[x\]')
echo "  已勾选: ${done_n}/${total}"

echo ""
echo "[6] 强制结尾段落"
grep -q "## 🚀 下一批接力提示词" "$L12" && echo "  ✅ 接力提示词" || echo "  ❌ 接力提示词缺失"
grep -q "## 🧭 课程导航" "$L12" && echo "  ✅ 课程导航" || echo "  ❌ 课程导航缺失"

echo ""
echo "[7] 四处档案"
for f in "00-学习档案.md" "00-评审清单.md" "stages/5-生产落地/README.md" "02-课程目录.md" "01-学习路径总览.md"; do
  if grep -q "2026-09-03" "$f" 2>/dev/null; then
    printf "  ✅ %-40s 含 2026-09-03 更新\n" "$f"
  else
    printf "  ⚠️ %-40s 无 2026-09-03 标记\n" "$f"
  fi
done

echo ""
echo "[8] 三项遗留已标记为闭环"
grep -l "✅" stages/5-生产落地/README.md >/dev/null && \
  grep -c "~~.*~~ → ✅" stages/5-生产落地/README.md | xargs -I{} echo "  README 中划掉并闭环的遗留项: {} 条"

echo ""
echo "[9] 脚本完整性"
cd playground
printf "  l12-* 脚本: %s 个\n" "$(ls l12-*.sh 2>/dev/null | wc -l)"
printf "  l12r-* 补充脚本: %s 个\n" "$(ls l12r-*.sh 2>/dev/null | wc -l)"

echo ""
echo "======================================================================"
echo "校验完成"
echo "======================================================================"
