#!/usr/bin/env bash
# 课 7 评审核查：逐条回读原文核验
set -u
F="/mnt/d/projects/learning/grafana/stages/3-叫得醒/lessons/lesson-07-告警架构：规则在哪求值、状态怎么迁移.md"

echo "=========================================================="
echo " 课 7 评审核查：逐条回读原文核验"
echo "=========================================================="

echo ""
echo "### Learner 视角 ###"

echo ""
echo "Q1. 正文所有可执行命令（须单行）："
grep -n 'wsl -d Ubuntu' "$F" | sed 's/^/    /'

echo ""
echo "Q2. 实验预期结果（须含判据）："
grep -n -A3 '预期看到' "$F" | head -40 | sed 's/^/    /'

echo ""
echo "Q3. 环境依赖/未实测/待补测标注："
grep -nE '未实测|未触发|没有实际触发|课 8 若遇到|取决于你|留给你|⚠️' "$F" | sed 's/^/    /'

echo ""
echo "### Pedagogy 视角 ###"

echo ""
echo "Q4. 认知冲突是否指向真问题："
grep -n '打脸\|对不上\|20 秒到了，没通知\|更奇怪' "$F" | head -6 | sed 's/^/    /'

echo ""
echo "Q5. 六要素各知识点实际小节："
for kp in 7.1 7.2 7.3; do
  echo "  --- $kp ---"
  awk -v kp="$kp" '
    $0 ~ ("知识点 " kp) {f=1}
    f && /^#### /{print "    "$0}
    f && /^### 知识点 7\.[23]/ && $0 !~ ("知识点 " kp) {f=0}
    f && /^## 🛠 第四幕/ {f=0}
  ' "$F"
done

echo ""
echo "### 数据事实核对（回读原文 vs 实测日志）###"

echo ""
echo "Q6. 关键数字上下文："
grep -nE '60\.1|10\.0|55\.1|规则组数 = 0|interval = 1m|up=0\.0' "$F" | head -12 | sed 's/^/    /'

echo ""
echo "Q7. KeepLast 拼写相关表述（须准确）："
grep -nE 'KeepLast' "$F" | head -10 | sed 's/^/    /'

echo ""
echo "Q8. 修正概览/档案的表述（须与实测一致）："
grep -nE '修正阶段 3|修正课 6|默认行为是|provisioning API 无默认值' "$F" | head -8 | sed 's/^/    /'

echo ""
echo "Q9. 「Grafana 揽活」跨课收束表（须与课4/5/6一致）："
grep -n -A8 '| 课 | 什么活 | 谁干 |' "$F" | head -12 | sed 's/^/    /'

echo ""
echo "Q10. 自我纠错/预判被推翻是否如实记录："
grep -nE '我搞错|我测错|我起疑|推翻|踩坑|两次失败|误判' "$F" | head -10 | sed 's/^/    /'

echo ""
echo "Q11. 状态标签写法（状态+原因）是否与 annotations 一致："
grep -n 'Alerting (NoData)\|Alerting (Error)\|Normal (Error)\|状态 (原因)' "$F" | head -8 | sed 's/^/    /'

echo ""
echo "Q12. 6 种状态表（须与 /metrics 实测一致）："
grep -n -A10 '| state 标签 | 对应概念 |' "$F" | head -13 | sed 's/^/    /'

echo ""
echo "=========================================================="
