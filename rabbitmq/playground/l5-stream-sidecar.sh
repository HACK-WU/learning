#!/usr/bin/env bash
# 从共享 rabbitmq-learn 网络的临时容器里跑 stream 回放测试
# 用 --network container:rabbitmq-learn 共享网络命名空间 → 127.0.0.1:5552 可达
set -u
PG=/mnt/d/projects/learning/rabbitmq/playground

docker run --rm \
  --network container:rabbitmq-learn \
  -v "$PG:/work" \
  -w /work \
  python:3.12-slim \
  sh -c '
    pip install --quiet rstream 2>&1 | tail -2
    echo "=== 开始测试 ==="
    python l5-stream-final.py 2>&1
  ' 2>&1
