#!/bin/bash
# 卫生与合规终检：围栏闭合 / 三态分工 / 阶段覆盖 / 紧急度
cd /mnt/d/projects/learning/surrealdb || exit 1

echo "===== 代码围栏闭合（应为偶数）====="
for f in final-课程手册.md 08-实战经验.md 09-排障速查手册.md 10-场景解法库.md; do
  n=$(grep -c '^```' "$f")
  if [ $((n % 2)) -eq 0 ]; then st="OK(偶数)"; else st="❌奇数"; fi
  printf "  %-24s 围栏=%-4s %s\n" "$f" "$n" "$st"
done

echo ""
echo "===== 三态分工声明 ====="
for f in 08-实战经验.md 09-排障速查手册.md 10-场景解法库.md; do
  printf "  %-24s 学习态=%s 使用态=%s 设计态=%s\n" "$f" \
    "$(grep -c '学习态' "$f")" "$(grep -c '使用态' "$f")" "$(grep -c '设计态' "$f")"
done

echo ""
echo "===== 10 场景库覆盖的课时 ====="
grep -o '课 [0-9]*' 10-场景解法库.md | sort -u -t' ' -k2 -n | tr '\n' ' '
echo ""
echo "-- 覆盖知识点编号（应分散于 1-12 课）:"
grep -o '知识点 [0-9]*\.[0-9]*' 10-场景解法库.md | sort -u -t' ' -k2 -n | tr '\n' ' '
echo ""

echo ""
echo "===== 08 反模式与 Checklist 规模 ====="
echo "-- 反模式条目: $(grep -cE '^\| [^-|].*\|.*\|.*\|' 08-实战经验.md) (含表格，非精确)"
echo "-- 上线前 Checklist: $(grep -c '^- \[ \]' 08-实战经验.md)"
echo "-- 静默失败清单条目: $(awk '/静默失败全清单/,/^---$/' 08-实战经验.md | grep -cE '^\| [0-9]+ \|')"

echo ""
echo "===== 09 紧急度与交叉引用 ====="
echo "-- 转其他症状的出口数: $(grep -c '转「症状\|转 \[症状' 09-排障速查手册.md)"
echo "-- 转 debug 的出口数: $(grep -c 'debug' 09-排障速查手册.md)"
echo "-- 毁现场警告段: $(grep -c '毁现场' 09-排障速查手册.md)"
echo "-- 通用纪律段: $(grep -c '^### 纪律' 09-排障速查手册.md)"

echo ""
echo "===== final 手册收束完整性 ====="
echo "-- 三份产物入口表: $(grep -c '08-实战经验\|09-排障速查手册\|10-场景解法库' final-课程手册.md)"
echo "-- Mermaid 图数量: $(grep -c 'mermaid' final-课程手册.md)"
