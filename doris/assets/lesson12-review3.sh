#!/bin/bash
# 课 12 评审 3（pedagogy 视角）：教学自洽性检查
# 重点查：故事线是否连贯、概念是否前后一致、是否有自相矛盾、是否有未兑现的承诺

LESSON="stages/4-分布式运维与生产落地/lessons/lesson-12-选型存算分离与场景落地.md"
BODY=$(awk '/^## 🚀 下一批接力提示词/{skip=1;next} /^## 🧭 课程导航/{skip=0} skip==0{print}' "$LESSON")

echo "############ A. 故事主线一致性 ############"
echo ""
echo "--- 骨架预设的问题：『我们这个场景，到底该不该用 Doris？』 ---"
grep -c "该不该用 Doris" "$LESSON" | xargs -I{} echo "  正文中出现『该不该用 Doris』{} 次"
grep -q "该不该用 Doris" <<< "$(sed -n '/## 第一幕/,/## 第二幕/p' "$LESSON")" && echo "  [OK] 第一幕提出了主线问题" || echo "  [WARN] 第一幕未提主线问题"
grep -q "该不该用 Doris" <<< "$(sed -n '/## 第五幕/,/## 🐞/p' "$LESSON")" && echo "  [OK] 第五幕回答了主线问题" || echo "  [WARN] 第五幕未回答主线问题"

echo ""
echo "############ B. 第二幕的『认知冲突』是否成立 ############"
echo "  骨架要求：『都说 Doris 快，那为什么不是所有场景都用它？』"
grep -q "认知冲突" <<< "$BODY" && echo "  [OK] 有认知冲突小节" || echo "  [WARN] 缺认知冲突"
grep -q "列数翻了 13 倍" <<< "$BODY" && echo "  [OK] 有列存冲突的实测数据" || echo "  [WARN] 缺列存冲突数据"
grep -q "货轮送外卖" <<< "$BODY" && echo "  [OK] 有点查冲突的类比" || echo "  [WARN] 缺点查冲突类比"

echo ""
echo "############ C. 三幕结构的知识点覆盖 ############"
for kp in "1.1 对比的正确姿势" "1.2 实测：列存的收益" "1.3 实测：倒排索引" "1.4 实测：Doris 抢不了的场景" "1.5 实测：Doris 抢不了的场景" "1.6 能力边界一览" "1.7 多系统并存" \
          "2.1 先确认本机是什么架构" "2.2 存算分离的语法" "2.3 用 S3 TVF" "2.4 本地性代价实测：聚合" "2.5 本地性代价实测：明细" "2.6 存算分离到底换了什么" "2.7 弹性" "2.8 选型判据" \
          "3.1 典型场景 1" "3.2 典型场景 2" "3.3 典型场景 3" "3.4 反模式 1" "3.5 反模式 2" "3.6 反模式 3" "3.7 反模式 4" "3.8 反模式 5" "3.9 决策清单"; do
  grep -qF "$kp" <<< "$BODY" && echo "  [OK] $kp" || echo "  [MISS] $kp"
done

echo ""
echo "############ D. 骨架要求的『交叉验证提示』是否兑现 ############"
echo "  骨架原文：课 9 的多副本与自动修复基于存算一体架构。本课讲存算分离时，"
echo "            须回头对照课 9 说明：存算分离下数据可靠性由共享存储层承担，"
echo "            副本语义与扩缩容行为均不同。"
grep -q "对照课 9" <<< "$BODY" && echo "  [OK] 有『对照课 9』" || echo "  [MISS] 缺『对照课 9』"
grep -q "课 9 讲过多副本" <<< "$BODY" && echo "  [OK] 有回扣课 9 多副本" || echo "  [MISS] 缺回扣课 9 多副本"
grep -qE "可靠性(由|交给)共享存储层承担" <<< "$BODY" && echo "  [OK] 说了可靠性由共享存储层承担" || echo "  [MISS] 未说可靠性归属"
grep -q "扩缩容" <<< "$(sed -n '/2.6 存算分离到底换了什么/,/2.7/p' <<< "$BODY")" && echo "  [OK] 2.6 节说了扩缩容行为差异" || echo "  [MISS] 2.6 节缺扩缩容差异"

echo ""
echo "############ E. 本课目标是否全部达成 ############"
echo "  目标 1：在 ClickHouse / Elasticsearch / Hive+Spark 之间做出有理有据的选型"
grep -q "ClickHouse" <<< "$BODY" && echo "     [OK] 提到 ClickHouse" || echo "     [MISS] 未提 ClickHouse"
grep -q "Elasticsearch" <<< "$BODY" && echo "     [OK] 提到 Elasticsearch" || echo "     [MISS] 未提 ES"
grep -q "Hive" <<< "$BODY" && echo "     [OK] 提到 Hive" || echo "     [MISS] 未提 Hive"
echo "  目标 2：说清存算分离解决什么问题、付出什么代价"
grep -q "存算分离解决什么问题\|存算分离的核心价值" <<< "$BODY" && echo "     [OK] 说清了解决什么" || echo "     [MISS] 未说清收益"
grep -q "付出的代价" <<< "$BODY" && echo "     [OK] 说清了代价" || echo "     [MISS] 未说清代价"
echo "  目标 3：说出至少 3 个不该用 Doris 的场景及替代方案"
N=$(grep -cE "^#### 3\.[0-9]+ 反模式" <<< "$BODY")
echo "     反模式数量：$N （要求 >=3）"

echo ""
echo "############ F. 自相矛盾检查 ############"
echo "--- F1: 是否一边说『不实测同类系统』一边给了对比数字 ---"
if grep -qE "ClickHouse.*[0-9]+\.[0-9]+ *[秒s]" <<< "$BODY"; then
  echo "  [CONFLICT] 出现 ClickHouse 具体耗时"
else
  echo "  [OK] 未出现 ClickHouse 具体耗时"
fi
echo "--- F2: 是否标了未实测却又当成事实陈述 ---"
grep -n "原理推演" <<< "$BODY" | head -8
echo "--- F3: 点查数据的两处表述是否一致 ---"
grep -oE "5\.[0-9]+ *~ *[0-9]+\.[0-9]+ *ms" <<< "$BODY" | sort -u
grep -oE "[0-9]+ *~ *[0-9]+ *QPS" <<< "$BODY" | sort -u
echo "--- F4: 明细 3 倍的表述是否一致 ---"
grep -oE "差 [0-9]+ 倍" <<< "$BODY" | sort | uniq -c

echo ""
echo "############ G. 全课程收束（本课是最后一课） ############"
grep -q "全课程完结" "$LESSON" && echo "  [OK] 有全课程完结标记" || echo "  [WARN] 缺完结标记"
grep -q "36 *个知识点\|36/36" "$LESSON" && echo "  [OK] 有知识点总数" || echo "  [WARN] 缺知识点总数"
# 阶段回扣在第五幕，应在全文上检查（BODY 已排除接力段，不影响此项）
grep -q "阶段 1" "$LESSON" && grep -q "阶段 4" "$LESSON" && echo "  [OK] 有四个阶段的回扣" || echo "  [WARN] 缺阶段回扣"
echo "  接力提示词指向："
grep -E "Phase 3|综合实战" "$LESSON" | head -3

echo ""
echo "############ H. 数值口径一致（同一指标在多处是否同值） ############"
echo "--- 扫 1 列的耗时 ---"
grep -oE "0\.1[0-9]+ *[ ~-]+ *0\.1[0-9]+ *秒" <<< "$BODY" | sort -u | head -5
echo "--- 点查 QPS ---"
grep -oE "1[0-9]{2} *[~-] *1[0-9]{2} *QPS" <<< "$BODY" | sort -u
echo "--- 314 万行 ---"
grep -oE "314[ 万]*[0-9]*" <<< "$BODY" | sort -u | head -3
