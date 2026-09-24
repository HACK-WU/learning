#!/bin/bash
# 课 10 独立复审：不轻信自评，逐条回读原文核验
set -u
B=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
D=/mnt/d/projects/learning/kafka/kafka-python-client/stages/3-生产层-吞吐与可靠性/课10-消费者工程与并发模型.md

echo "########## 1. 脚本可执行性 ##########"
for s in l10_probe.sh l10_models.sh l10_diag_chunksize.sh l10_diag_chunksize2.sh l10_offset.sh l10_scale.sh; do
  if [ -f "$B/$s" ]; then
    out=$(bash "$B/$s" 2>&1)
    if echo "$out" | grep -q 'Traceback\|SyntaxError\|NameError\|TypeError'; then
      echo "  ✗ $s 异常"; echo "$out" | grep -E 'Error' | head -2
    else
      echo "  ✓ $s"
    fi
  else echo "  ✗ $s 不存在"; fi
done

echo ""
echo "########## 2. 讲义 GIL 数字 0.42 / 0.42 / 0.12 / 1.00x / 3.54x ##########"
bash "$B/l10_probe.sh" 2>&1 | grep -E '串行|4 线程|4 进程'

echo ""
echo "########## 3. 讲义表A 2880/2521/2551/4931/9840 ##########"
bash "$B/l10_models.sh" 2>&1 | sed -n '/A. CPU 密集/,/B\./p' | grep -E '串行|线程|进程'

echo ""
echo "########## 4. 讲义表B 1343/1933/2227/3199/6293 ##########"
bash "$B/l10_models.sh" 2>&1 | sed -n '/B. CPU/,$p' | grep -E '串行|线程|进程'

echo ""
echo "########## 5. 讲义 chunksize 表 0.71/2.72/2.92/2.93/2.80 ##########"
bash "$B/l10_diag_chunksize2.sh" 2>&1 | grep -E 'chunksize=|串行基线'

echo ""
echo "########## 6. 讲义扩容表 [1,1,1,1,0,0] ##########"
bash "$B/l10_scale.sh" 2>&1 | grep -E '^  [0-9] '

echo ""
echo "########## 7. 讲义引用脚本是否都存在 ##########"
sed -n '/^## 九、复现命令/,/^```$/p' "$D" | grep -oE 'l10[a-z0-9_]*\.sh' | sort -u | while read s; do
  [ -f "$B/$s" ] && echo "  ✓ $s" || echo "  ✗ 缺失: $s"
done

echo ""
echo "########## 8. 讲义本地链接可达性 ##########"
cd /mnt/d/projects/learning/kafka/kafka-python-client/stages/3-生产层-吞吐与可靠性
grep -oE '\]\([^)]+\.md\)' "$D" | sed 's/](//;s/)//' | sort -u | while read l; do
  [ -f "$l" ] && echo "  ✓ $l" || echo "  ✗ 死链: $l"
done
