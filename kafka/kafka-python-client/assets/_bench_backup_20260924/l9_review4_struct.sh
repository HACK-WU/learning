#!/bin/bash
# 课 9 独立复审（第 3 轮）：讲义结构性检查
# 1. 五幕结构 / 六要素 是否齐
# 2. 术语中英标注是否符合「命名三态」纪律
# 3. 是否有未实测却写成结论的地方
set -u
D=/mnt/d/projects/learning/kafka/kafka-python-client/stages/3-生产层-吞吐与可靠性/课9-序列化与SchemaRegistry.md

echo "===== A. 章节结构 ====="
grep -n '^#\{1,3\} ' "$D"

echo ""
echo "===== B. 表格数量（应 >= 6）====="
grep -c '^|' "$D"

echo ""
echo "===== C. 代码块数量 ====="
grep -c '^```' "$D"

echo ""
echo "===== D. 术语检查：首次出现是否带英文 ====="
for t in Schema Registry Avro wire format KRaft serializer; do
  c=$(grep -c "$t" "$D")
  echo "  $t : 出现 $c 次"
done

echo ""
echo "===== E. 检查讲义是否含『未实测』的模糊表述 ====="
grep -n -E '据说|一般认为|通常来说|应该会|大概是' "$D" || echo "  ✓ 无模糊表述"

echo ""
echo "===== F. 诚实标注段是否存在 ====="
grep -n -A6 '## 诚实标注' "$D" | head -10
