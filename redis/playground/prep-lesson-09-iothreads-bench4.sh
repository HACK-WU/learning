#!/bin/bash
# 用官方 redis-benchmark 重测 io-threads（修正输出解析）

echo "=== 先看 redis-benchmark -q 的原始输出格式 ==="
redis-benchmark -h 127.0.0.1 -p 7102 -n 50000 -c 50 -t get,set -q 2>&1 | head -10
echo "--- 加上 --threads 4 ---"
redis-benchmark -h 127.0.0.1 -p 7102 -n 50000 -c 50 --threads 4 -t get,set -q 2>&1 | head -10
