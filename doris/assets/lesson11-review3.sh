#!/bin/bash
# 课 11 评审 3（pedagogy 视角）：正文内部数据自洽性 + 与脚本产出是否对得上
L=/mnt/d/projects/learning/doris/stages/4-分布式运维与生产落地/lessons/lesson-11-日常运维SchemaChange备份与升级.md

echo "########## pedagogy 视角评审：数据与表述自洽性 ##########"

echo ""
echo "===== 1. 关键数字在正文里出现的所有位置（看有没有互相矛盾）====="
for n in "271" "304" "108" "143" "17" "18" "21" "1249998750000" "700000" "476" "19.82"; do
  CNT=$(grep -c "$n" "$L")
  echo "  '$n' 出现 $CNT 次"
done

echo ""
echo "===== 2. 耗时范围表述一致性 ====="
echo "--- light 范围 ---"
grep -oE "[0-9]{3} ?[–-] ?[0-9]{3} ?ms" "$L" | sort -u | sed 's/^/  /'
echo "--- 秒级范围 ---"
grep -oE "[0-9]{1,2} ?[–-] ?[0-9]{1,2} ?秒" "$L" | sort -u | sed 's/^/  /'

echo ""
echo "===== 3. 检查是否有矛盾表述（同一数字两种说法）====="
echo "--- 出现 '0.25' 与其他 qps 值冲突？---"
grep -nE "doris_fe_qps" "$L" | sed 's/^/  /'
echo "--- 副本倍数相关表述 ---"
grep -nE "副本倍数|零冗余" "$L" | sed 's/^/  /'

echo ""
echo "===== 4. 边界标记统计（每个知识点是否都标了）====="
echo "  🟢 出现 $(grep -c '🟢' "$L") 次"
echo "  🟡 出现 $(grep -c '🟡' "$L") 次"
echo "  🔴 出现 $(grep -c '🔴' "$L") 次"
echo "--- 边界表里列了几个知识点 ---"
awk '/实验边界/,/^---$/' "$L" | grep -cE '^\|' | sed 's/^/  边界表行数: /'

echo ""
echo "===== 5. 数值浮动说明是否到位 ====="
grep -nE "重跑会变|重跑会浮动|看量级|不要看绝对值|实测范围" "$L" | sed 's/^/  /'

echo ""
echo "===== 6. 检查是否还有未标注的推演（不能拿推演冒充实测）====="
grep -nE "推演|无法实测|无法演练|不能演练|未实测" "$L" | sed 's/^/  /'

echo ""
echo "===== 7. 五幕结构完整性 ====="
for s in "第一幕：起源与场景引入" "第二幕：认知冲突" "第三幕：层层揭示" "第四幕：实操验证" "第五幕：体系收束"; do
  if grep -q "$s" "$L"; then echo "  [OK]   $s"; else echo "  [FAIL] $s"; fi
done

echo ""
echo "===== 8. 第二幕的冲突点是否明确回扣 ====="
grep -nE "ALTER.*返回.*≠|返回成功.*≠|不是.*ALTER.*跑没跑完" "$L" | sed 's/^/  /'

echo ""
echo "===== 9. 三个知识点是否都有"小结" ====="
grep -nE "^#### 1\.[0-9]+ 知识点 1 小结|^#### 2\.1[0-9] 知识点 2 小结|^#### 3\.1[0-9] 知识点 3 小结" "$L" | sed 's/^/  /'

echo ""
echo "===== 10. 误区数量与小测 ====="
echo "  误区数: $(grep -cE '^### 误区 [0-9]+' "$L")"
echo "  小测数: $(grep -cE '^\*\*第 [0-9]+ 题\*\*' "$L")"
grep -nE '^### 误区 [0-9]+' "$L" | sed 's/^/  /'

echo ""
echo "===== 11. 与课 10 的接力提示词是否对得上（遗留待办）====="
echo "--- 课 10 说 enable_spill 未持久化 ---"
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW VARIABLES LIKE 'enable_spill';" 2>&1 | grep -v Warning | sed 's/^/  /'
echo "--- 课 10 说 disable_balance=false ---"
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW VARIABLES LIKE 'disable_balance';" 2>&1 | grep -v Warning | sed 's/^/  /'
echo "--- 课 10 说 Workload Group 只剩 normal ---"
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW WORKLOAD GROUPS;" 2>&1 | grep -v Warning | sed 's/^/  /'

echo ""
echo "===== 12. 正文行数与结构 ====="
echo "  总行数: $(wc -l < "$L")"
echo "--- 章节结构 ---"
grep -nE "^#{2,4} " "$L" | sed 's/^/  /'
