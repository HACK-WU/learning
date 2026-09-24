#!/bin/sh
# 吞吐基准执行器：在同一 docker 网络里跑两库对照
# 用法：bash run-bench.sh <轮次号> [消息条数]
#
# 为什么必须挂到 stage6-observability_kafka-net：
#   broker 的 advertised.listeners 是容器名 kafka-1:9092，
#   宿主机直连 19192 会拿到不可达地址（课 15 实测过的坑）。

set -e

ROUND=${1:-1}
COUNT=${2:-100000}

NET=stage6-observability_kafka-net
IMG=kafka-pybench:3.12
SRC=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench

echo "=== round $ROUND, messages=$COUNT ==="

docker run --rm --network "$NET" \
  -v "$SRC":/app/scripts \
  -e NUM_MESSAGES="$COUNT" \
  "$IMG" \
  /app/.venv/bin/python /app/scripts/bench_confluent.py "$ROUND"

docker run --rm --network "$NET" \
  -v "$SRC":/app/scripts \
  -e NUM_MESSAGES="$COUNT" \
  "$IMG" \
  /app/.venv/bin/python /app/scripts/bench_kafka_python.py "$ROUND"
