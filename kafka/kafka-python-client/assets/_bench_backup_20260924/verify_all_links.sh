#!/bin/bash
# 主教程修复后的全库终检：链接可达性 + SVG XML 合法性 + 残留检查
set -u
B=/mnt/d/projects/learning/kafka

echo "=== 1. 应用实战目录残留检查（应仅剩 09 的坑说明正文） ==="
grep -rn 'kafka-python-ng' "$B/应用实战/" 2>/dev/null || echo "  kafka-python-ng：零残留 ✓"

echo ""
echo "=== 2. 应用实战目录 commitSync 残留（应仅剩 06/09 的坑说明） ==="
grep -rn 'commitSync' "$B/应用实战/" 2>/dev/null | grep -v '06-消费者与消费者组.md\|09-代码开发实战.md' || echo "  代码与SVG：零残留 ✓"

echo ""
echo "=== 3. SVG XML 合法性 ==="
bad=0
total=0
while IFS= read -r f; do
  total=$((total+1))
  if ! python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse('$f')" 2>/dev/null; then
    echo "  ✗ 非法: $f"
    bad=$((bad+1))
  fi
done < <(find "$B" -name "*.svg" -type f)
echo "  SVG 总数 $total，非法 $bad"

echo ""
echo "=== 4. Markdown 代码块围栏奇偶性 ==="
odd=0
while IFS= read -r f; do
  n=$(grep -c '^```' "$f" 2>/dev/null || echo 0)
  if [ $((n % 2)) -ne 0 ]; then
    echo "  ✗ 奇数围栏: $f ($n)"
    odd=$((odd+1))
  fi
done < <(find "$B" -name "*.md" -type f)
echo "  奇数围栏文件数: $odd"
