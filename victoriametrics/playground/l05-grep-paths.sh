#!/bin/bash
# 定位课 5 讲义中所有路径写法，确认「容器内视角」与「宿主机视角」的混用范围
F="/mnt/d/projects/learning/victoriametrics/stages/3-凭什么快凭什么省/5-存储引擎MergeSet与磁盘结构.md"
echo "=== 含 data/data 的行 ==="
grep -n 'data/data' "$F"
echo
echo "=== 含 victoria-metrics-data 的行 ==="
grep -n 'victoria-metrics-data' "$F"
echo
echo "=== 含 data/ 但不含 data/data 的行 ==="
grep -n 'data/' "$F" | grep -v 'data/data'
