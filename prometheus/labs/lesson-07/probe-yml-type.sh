#!/usr/bin/env bash
cd /d/projects/learning/prometheus/labs/lesson-07 || exit 1
echo "=== prometheus.yml 到底是什么 ==="
ls -la prometheus.yml 2>&1
echo
echo "=== 如果是目录，里面有什么 ==="
ls -la prometheus.yml/ 2>&1 | head -n 10
echo
echo "=== 用 python 确认 ==="
python -c "
import os
p = r'D:/projects/learning/prometheus/labs/lesson-07/prometheus.yml'
print('exists:', os.path.exists(p))
print('isdir :', os.path.isdir(p))
print('isfile:', os.path.isfile(p))
"
echo
echo "=== 同级其他 yml 是否正常 ==="
ls -la *.yml 2>&1
