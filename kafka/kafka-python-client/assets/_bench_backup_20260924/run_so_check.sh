#!/bin/bash
# 在干净容器里逐个安装并检查 .so
set -u
W=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
IMG=python:3.12-slim

run_one() {
  local spec="$1"
  echo "########## ${spec} ##########"
  docker run --rm -v "$W:/w" "$IMG" \
    bash -c "pip install -q ${spec} >/dev/null 2>&1; python /w/verify_so_files.py"
  echo ""
}

run_one "kafka-python==3.0.11"
run_one "confluent-kafka==2.15.1"
run_one "aiokafka==0.14.0"
