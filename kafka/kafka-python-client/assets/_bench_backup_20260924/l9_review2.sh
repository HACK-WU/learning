#!/bin/bash
# 课 9 独立复审（第 2 轮）：核验讲义里的每个关键数字与断言
# 铁律：不重跑就下结论 = 没审。这里逐条回读实测输出
set -u
B=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
D=/mnt/d/projects/learning/kafka/kafka-python-client/stages/3-生产层-吞吐与可靠性/课9-序列化与SchemaRegistry.md

echo "########## 复审项 1：体积数字 162 / 62 / 439 / 178 ##########"
bash "$B/l9_format_compare.sh" 2>&1 | grep -E 'JSON（无|Avro（schema|Avro \+ 内嵌|JSON \+ type' 

echo ""
echo "########## 复审项 2：吞吐数字 504354 / 430059 ##########"
bash "$B/l9_format_compare.sh" 2>&1 | grep -E '^JSON|^Avro \(fastavro'

echo ""
echo "########## 复审项 3：六种演进结论 ##########"
bash "$B/l9_avro_compat.sh" 2>&1 | grep -E '演进类型|^新字段|^删字段|^int->long|^long->int|^改字段名'

echo ""
echo "########## 复审项 4：策略矩阵 ##########"
bash "$B/l9_compat_policy.sh" 2>&1 | grep -A6 '矩阵汇总' | tail -5

echo ""
echo "########## 复审项 5：真 SR 关键断言（409 拒绝 / 幂等 / wire format）##########"
bash "$B/l9_real_sr.sh" 2>&1 | grep -E '^\[[0-9]+\]'

echo ""
echo "########## 复审项 6：端到端 10/10 与 currency 自动填充 ##########"
bash "$B/l9_e2e_real_sr.sh" 2>&1 | grep -E '总条数|V1-|V2-|backward 兼容兑现'
