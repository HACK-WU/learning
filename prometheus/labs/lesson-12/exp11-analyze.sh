#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
PT="docker run --rm -v $D:/w --entrypoint promtool prom/prometheus:v3.14.0"

echo "===== tsdb analyze（全库） ====="
$PT tsdb analyze /w/blocks-out 2>&1 | head -30

echo
echo "===== tsdb analyze 指定单个 block ====="
BLK=$(docker exec l12-prom sh -c "ls /w/blocks-out | head -1" 2>/dev/null || ls $D/blocks-out | head -1)
echo "block = $BLK"
$PT tsdb analyze /w/blocks-out "$BLK" 2>&1 | head -25
