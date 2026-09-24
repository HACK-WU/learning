#!/bin/bash
# 课 9 复审（第 2 轮，针对 Protobuf 补齐）
# 核验新增章节的每个数字，不允许「写完就交」
set -u
B=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
D=/mnt/d/projects/learning/kafka/kafka-python-client/stages/3-生产层-吞吐与可靠性/课9-序列化与SchemaRegistry.md

echo "########## 1. 新增脚本可执行性 ##########"
for s in l9_protobuf.sh l9_pb_sr.sh l9_pb_verify.sh; do
  if [ -f "$B/$s" ]; then
    out=$(bash "$B/$s" 2>&1)
    if echo "$out" | grep -q 'Traceback\|SyntaxError\|NameError'; then
      echo "  ✗ $s 有异常"; echo "$out" | grep -E 'Error' | head -2
    else
      echo "  ✓ $s 正常执行"
    fi
  else
    echo "  ✗ $s 不存在"
  fi
done

echo ""
echo "########## 2. 讲义体积数字 88 / 32 / 37 ##########"
bash "$B/l9_protobuf.sh" 2>&1 | grep -E '^    (JSON|Avro|Protobuf) +[0-9]+ '

echo ""
echo "########## 3. 讲义吞吐数字 535976 / 780501 / 1880147 ##########"
bash "$B/l9_protobuf.sh" 2>&1 | grep -E '^    (JSON|Avro|Protobuf) +[0-9,]+ +[0-9,]+'

echo ""
echo "########## 4. 测法对比表 6517458 / 2136465 / 2076020 ##########"
bash "$B/l9_pb_verify.sh" 2>&1 | grep -E 'A\.|B\.|C\.|Avro \(|JSON'

echo ""
echo "########## 5. Protobuf+SR 断言 ##########"
bash "$B/l9_pb_sr.sh" 2>&1 | grep -E '^\[[0-9]\]'

echo ""
echo "########## 6. 讲义引用完整性（新增脚本）##########"
sed -n '/^## 九、复现命令/,/^```$/p' "$D" | grep -oE 'l9[a-z0-9_]*\.sh' | sort -u | while read s; do
  [ -f "$B/$s" ] && echo "  ✓ $s" || echo "  ✗ 缺失: $s"
done
