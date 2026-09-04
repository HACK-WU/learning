#!/bin/bash
# 课 10 评审辅助 3：pedagogy 视角 —— 正文数据自洽性与前后一致性
LESSON="/mnt/d/projects/learning/doris/stages/4-分布式运维与生产落地/lessons/lesson-10-资源隔离与负载管理.md"
echo "===== 1. 五幕结构 ====="
for sec in "第一幕" "第二幕" "第三幕" "第四幕" "第五幕"; do
  if grep -q "## $sec" "$LESSON"; then echo "  [OK] 含 $sec"; else echo "  [FAIL] 缺 $sec"; fi
done

echo ""
echo "===== 2. 三个知识点标题 ====="
for kp in "知识点 1：Workload Group 与资源隔离" "知识点 2：内存管理" "知识点 3：查询并发与队列控制"; do
  if grep -q "$kp" "$LESSON"; then echo "  [OK] 含 $kp"; else echo "  [FAIL] 缺 $kp"; fi
done

echo ""
echo "===== 3. 收尾段落 ====="
for s in "## 🐞 常见误区" "## ⚡ 速览模式" "## 🎓 课后小测" "## 🚀 下一批接力提示词" "## 🧭 课程导航"; do
  if grep -q "$s" "$LESSON"; then echo "  [OK] 含 $s"; else echo "  [FAIL] 缺 $s"; fi
done

echo ""
echo "===== 4. 边界标注（课 9 起强制项）====="
for m in "实验边界" "🟢 已实测" "🟡" "cgroup"; do
  n=$(grep -c "$m" "$LESSON")
  echo "  [$m] 出现 $n 次"
done

echo ""
echo "===== 5. 主线数据自洽性：三处引用是否一致 ====="
echo "  --- 第二幕（无隔离）应该出现的耗时 ---"
grep -nE "^\s*(1223|1260|1476|1492|1719)" "$LESSON" | head -8 | sed 's/^/    /'
echo "  --- 第三幕 1.7（有隔离）---"
grep -nE "\b(212|217|218|230|233|237|265|270)\b ms|212–265|217–270" "$LESSON" | head -6 | sed 's/^/    /'
echo "  --- 基线 ---"
grep -nE "147|171|153|186" "$LESSON" | grep -iE "基线|ms" | head -6 | sed 's/^/    /'

echo ""
echo "===== 6. Spill 数据自洽性（重跑后已修正，检查是否还有旧值）====="
echo "  应无：0.35-0.38 / 8.79-13.77 / 落盘峰值 36 MB / 慢 25-40 倍"
grep -nE "0\.35–0\.38|0\.35-0\.38|8\.79|13\.77|36 ?MB|25–40|25-40" "$LESSON" | sed 's/^/    /'
echo "  （以上为空表示已全部修正）"

echo ""
echo "===== 7. 应有：修正后的值 ====="
echo "  应有：0.30-0.33 / 5.24-11.85 / 落盘峰值 40 MB / 慢 17-39 倍"
grep -cE "0\.30[–-]0\.33" "$LESSON" | sed 's/^/    0.30-0.33 出现次数: /'
grep -cE "5\.24|11\.85" "$LESSON" | sed 's/^/    5.24 或 11.85 出现次数: /'
grep -cE "40 ?MB" "$LESSON" | sed 's/^/    40MB 出现次数: /'
grep -cE "17[–-]39" "$LESSON" | sed 's/^/    17-39 出现次数: /'

echo ""
echo "===== 8. 前后矛盾检查：同一指标是否出现两个不同数值 ====="
echo "  --- enable_spill 默认值 ---"
grep -n "enable_spill.*默认" "$LESSON" | head -4 | sed 's/^/    /'
echo "  --- max_concurrency 默认值 ---"
grep -n "2147483647" "$LESSON" | head -4 | sed 's/^/    /'
echo "  --- 组数上限 ---"
grep -nE "最多 15|上限 15|exceed 15" "$LESSON" | head -4 | sed 's/^/    /'

echo ""
echo "===== 9. 误区数量与速览覆盖度 ====="
echo "  常见误区条数: $(grep -cE '^### 误区 [0-9]+' "$LESSON")"
echo "  课后小测题数: $(grep -cE '^### 第 [0-9]+ 题' "$LESSON")"
echo "  <details> 答案块: $(grep -c '<details>' "$LESSON")"

echo ""
echo "===== 10. 导航链接 ====="
for l in "lesson-09-副本高可用与扩缩容.md" "lesson-11-日常运维SchemaChange备份与升级.md" "../../../02-课程目录.md" "../overview.md"; do
  if grep -q "$l" "$LESSON"; then echo "  [OK] $l"; else echo "  [FAIL] $l"; fi
done

echo ""
echo "===== 11. 正文行数 ====="
wc -l < "$LESSON" | sed 's/^/  /'
