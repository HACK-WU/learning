#!/bin/bash
# 课 8 交付后最终一致性校验
ES='curl.exe -s -k -u elastic:RyL6CsxCsFCTMEcTZbru -H Content-Type:application/json'
BASE="/mnt/d/projects/learning/elasticsearch"
L8="$BASE/stages/3-查询与聚合/lessons/lesson-08-聚合不做搜索做统计.md"

echo "===== 1. 进度文件课8状态一致性 ====="
for f in "00-学习档案.md" "01-学习路径总览.md" "02-课程目录.md" "00-评审清单.md" "stages/3-查询与聚合/overview.md"; do
  echo "--- $f"
  grep -n "课8\|课 8" "$BASE/$f" 2>/dev/null | cut -c1-120
done

echo ""
echo "===== 2. 讲义文件完整性 ====="
echo "行数: $(wc -l < "$L8")"
echo "字节: $(wc -c < "$L8")"
echo "围栏数(应为偶数): $(grep -c '^\`\`\`' "$L8")"

echo ""
echo "===== 3. 讲义引用的索引是否都存在 ====="
for idx in l8_orders l8_orders_v2 l8_text_demo l7_news l6_shop; do
  cnt=$($ES "https://localhost:9200/$idx/_count" | grep -o '"count":[0-9]*' | head -1)
  echo "$idx -> $cnt"
done

echo ""
echo "===== 4. 讲义关键数字 vs ES 实算 ====="
echo "--- 期望 苹果80390/华为64179/小米45488, 均价 8849.0/6497.625/4236.5"
cat > /tmp/q1.json <<'EOF'
{"size":0,"aggs":{"by_brand":{"terms":{"field":"brand","size":10},"aggs":{"s":{"sum":{"field":"amount"}},"a":{"avg":{"field":"unit_price"}}}}}}
EOF
$ES "https://localhost:9200/l8_orders_v2/_search?size=0" -d @/tmp/q1.json | tr ',' '\n' | grep -E '"key"|"sum"|"avg"' | cut -c1-80

echo ""
echo "--- 期望 总额 190057"
$ES "https://localhost:9200/l8_orders_v2/_search?size=0" -d '{"size":0,"aggs":{"t":{"sum":{"field":"amount"}}}}' | grep -o '"value":[0-9.]*'

echo ""
echo "===== 5. 讲义索引引用次数 ====="
echo "l8_text_demo: $(grep -c 'l8_text_demo' "$L8")"
echo "l8_orders_v2: $(grep -c 'l8_orders_v2' "$L8")"
echo "l8_orders(精确词): $(grep -c 'l8_orders[^_]' "$L8")"

echo ""
echo "===== 6. 讲义末段结构 ====="
grep -n '^## ' "$L8" | tail -6
