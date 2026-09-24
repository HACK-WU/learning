#!/bin/bash
# 复审 R1 修正：grep 模式漏了含数字的文件名
set -u
DOC=/mnt/d/projects/learning/kafka/kafka-python-client/stages/3-生产层-吞吐与可靠性/课9-序列化与SchemaRegistry.md
B=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
echo "=== 讲义第 9 节列出的复现命令 ==="
sed -n '/^## 九、复现命令/,/^```$/p' "$DOC" | grep -o 'l9[a-z0-9_]*\.sh' | sort -u > /tmp/doc_scripts.txt
cat /tmp/doc_scripts.txt
echo ""
echo "=== 逐个核验是否存在 ==="
while read s; do
  [ -z "$s" ] && continue
  if [ -f "$B/$s" ]; then echo "  ✓ $s"
  else echo "  ✗ 缺失: $s  <- 讲义写了但文件不存在，读者照抄会失败"; fi
done < /tmp/doc_scripts.txt
echo ""
echo "=== bench 目录下实际存在的 l9 脚本 ==="
ls "$B" | grep -E '^l9.*\.sh$' | sort
