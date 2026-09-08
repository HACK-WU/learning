#!/bin/bash
echo "=== 讲义 ==="
wc -l /mnt/d/projects/learning/prometheus/stages/2-规则与告警/lessons/lesson-05-Alertmanager深入.md

echo ""
echo "=== 章节 ==="
grep -n '^## ' /mnt/d/projects/learning/prometheus/stages/2-规则与告警/lessons/lesson-05-Alertmanager深入.md

echo ""
echo "=== 实验目录 ==="
ls /mnt/d/projects/learning/prometheus/labs/lesson-05/
echo "--- app ---"
ls /mnt/d/projects/learning/prometheus/labs/lesson-05/app/

echo ""
echo "=== 清理临时诊断文件 ==="
cd /mnt/d/projects/learning/prometheus/labs/lesson-05
rm -f diag-fail.sh diag-fail5.sh probe.sh chk.sh env-check.sh probe-silence.sh \
      diagnose-pollution.py diagnose2.py fix-jq.sh check-curl.sh state-check.sh \
      final-state.sh append-factcheck.py.bak 2>/dev/null
rm -rf app/__pycache__ __pycache__ 2>/dev/null
rm -f /mnt/d/projects/learning/prometheus/00-学习档案.md.bak \
      /mnt/d/projects/learning/prometheus/00-学习档案.md.bak2 2>/dev/null
echo "cleaned"

echo ""
echo "=== 保留的文件 ==="
ls /mnt/d/projects/learning/prometheus/labs/lesson-05/
