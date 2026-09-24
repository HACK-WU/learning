#!/bin/bash
# 课 1 实操：uv 虚拟环境搭建全流程实测
# 验证 uv 能否在容器内建 venv 并装三库
set -u
IMG=python:3.12-slim
W=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench

echo "=== 1. uv 版本 ==="
docker run --rm -v "$W:/w" "$IMG" \
  bash -c "pip install -q uv >/dev/null 2>&1; uv --version"

echo ""
echo "=== 2. uv venv 创建 + 装三库（体验 uv 的速度） ==="
docker run --rm -v "$W:/w" "$IMG" \
  bash -c "pip install -q uv >/dev/null 2>&1
    time uv venv /tmp/kfk-venv 2>&1 | tail -2
    echo '--- 装 kafka-python + confluent-kafka + aiokafka ---'
    VIRTUAL_ENV=/tmp/kfk-venv time uv pip install kafka-python==3.0.11 confluent-kafka==2.15.1 aiokafka==0.14.0 2>&1 | tail -8"

echo ""
echo "=== 3. 验证 venv 内三库可同时导入 ==="
docker run --rm -v "$W:/w" "$IMG" \
  bash -c "pip install -q uv >/dev/null 2>&1
    uv venv /tmp/kfk-venv >/dev/null 2>&1
    VIRTUAL_ENV=/tmp/kfk-venv uv pip install -q kafka-python==3.0.11 confluent-kafka==2.15.1 aiokafka==0.14.0 >/dev/null 2>&1
    /tmp/kfk-venv/bin/python -c \"
import kafka, confluent_kafka, aiokafka
print('kafka          ', kafka.__version__)
print('confluent_kafka', confluent_kafka.__version__)
print('aiokafka       ', aiokafka.__version__)
print('三库可共存 ✓')
\""

echo ""
echo "=== 4. uv pip 与 pip 速度对比（同一库） ==="
docker run --rm -v "$W:/w" "$IMG" \
  bash -c "pip install -q uv >/dev/null 2>&1
    echo '--- pip ---'
    ( time pip install -q --force-reinstall --no-deps kafka-python==3.0.11 ) 2>&1 | grep real
    echo '--- uv pip ---'
    uv venv /tmp/v2 >/dev/null 2>&1
    ( time VIRTUAL_ENV=/tmp/v2 uv pip install -q --no-deps kafka-python==3.0.11 ) 2>&1 | grep real"
