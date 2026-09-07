#!/usr/bin/env bash
# 课 6 双视角评审核查：逐条回读原文核验
set -u

F="/mnt/d/projects/learning/grafana/stages/2-查得到/lessons/lesson-06-变量进阶与动态仪表盘.md"

echo "=========================================================="
echo " 课 6 评审核查：逐条回读原文核验"
echo "=========================================================="

echo ""
echo "### Learner 视角：读者照抄能跑通吗 ###"

echo ""
echo "Q1. 正文所有可执行命令（须单行）："
grep -n 'wsl -d Ubuntu' "$F" | sed 's/^/    /'

echo ""
echo "Q2. 实验预期结果（须含判据）："
grep -n -A3 '预期看到' "$F" | head -40 | sed 's/^/    /'

echo ""
echo "Q3. 环境依赖/数值浮动/推算标注："
grep -nE '推算值|未在真实|取决于你的|留给你|未演示|⚠️' "$F" | sed 's/^/    /'

echo ""
echo "### Pedagogy 视角 ###"

echo ""
echo "Q4. 认知冲突指向真问题："
grep -n '逗号分隔的多值，一个点都查不出来\|选 2 台.*图空了\|打脸' "$F" | head -4 | sed 's/^/    /'

echo ""
echo "Q5. 六要素各知识点实际小节："
for kp in 6.1 6.2 6.3; do
  echo "  --- $kp ---"
  awk -v kp="$kp" '
    $0 ~ ("知识点 " kp) {f=1}
    f && /^#### /{print "    "$0}
    f && /^### 知识点 6\.[23]/ && $0 !~ ("知识点 " kp) {f=0}
    f && /^## 🛠 第四幕/ {f=0}
  ' "$F"
done

echo ""
echo "### 数据事实核对 ###"

echo ""
echo "Q6. 正文关键数字上下文（21/42/480/21.8/726）："
grep -nE '21 点|42 点|480|21\.8|726|76177' "$F" | head -14 | sed 's/^/    /'

echo ""
echo "Q7. 修正课 4 的表述是否准确（须与实测一致）："
grep -nE '语法错|0 帧|bad_data|404' "$F" | grep -iE '课 4|修正|实测' | head -8 | sed 's/^/    /'

echo ""
echo "Q8. 与课 5 的「存后端跑前端」是否一致："
grep -n '存后端、跑前端\|存后端\|跑前端' "$F" | head -6 | sed 's/^/    /'

echo ""
echo "Q9. F1/F2/F3/F4 判据表是否与实测输出一致："
grep -n -A8 '| 失败类型 | HTTP | 帧数' "$F" | head -12 | sed 's/^/    /'

echo ""
echo "Q10. 自我纠错/预判被推翻是否如实记录："
grep -n '预判\|我原本\|一度以为\|推翻\|修正' "$F" | head -10 | sed 's/^/    /'

echo ""
echo "=========================================================="
