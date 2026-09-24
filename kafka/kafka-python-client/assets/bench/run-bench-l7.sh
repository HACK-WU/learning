#!/bin/sh
# 课 7 吞吐调优对照执行器
#
# 三组对照（解决预研只跑 none 基线、缺调优数据的缺口）：
#   A. 基线        : compression=none  linger=10   (复现预研)
#   B. 压缩对照    : none / gzip / snappy / lz4 / zstd
#   C. linger 对照 : 0 / 10 / 50 / 100 ms
#
# 用法：bash run-bench-l7.sh <组号 A|B|C> [消息条数]
set -e

GROUP=${1:-A}
COUNT=${2:-50000}
NET=stage6-observability_kafka-net
IMG=kafka-pybench:3.12
SRC=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench

run_pair () {
  LABEL=$1; shift
  echo ""
  echo "===== $LABEL ====="
  docker run --rm --network "$NET" -v "$SRC":/app/scripts \
    -e NUM_MESSAGES="$COUNT" "$@" "$IMG" \
    /app/.venv/bin/python /app/scripts/bench_confluent.py "$LABEL" 2>&1 \
    | grep -v -e 'rdkafka#' -e 'Unclosed'
  docker run --rm --network "$NET" -v "$SRC":/app/scripts \
    -e NUM_MESSAGES="$COUNT" "$@" "$IMG" \
    /app/.venv/bin/python /app/scripts/bench_kafka_python.py "$LABEL" 2>&1 \
    | grep -v -e 'rdkafka#' -e 'Unclosed'
}

case "$GROUP" in
  A)
    run_pair "A-none-l10"    -e COMPRESSION=none -e LINGER_MS=10
    ;;
  B)
    for c in none gzip snappy lz4 zstd; do
      run_pair "B-$c-l10"    -e COMPRESSION="$c" -e LINGER_MS=10
    done
    ;;
  C)
    for l in 0 10 50 100; do
      run_pair "C-none-l$l"  -e COMPRESSION=none -e LINGER_MS="$l"
    done
    ;;
  *)
    echo "用法: bash run-bench-l7.sh <A|B|C> [消息条数]"
    exit 1
    ;;
esac
