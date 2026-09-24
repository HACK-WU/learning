#!/bin/bash
# 课 3：消费组与位移查询实测 v2
set -u
NET=stage6-observability_kafka-net
W=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
IMG=python:3.12-slim

docker run --rm --network "$NET" -v "$W:/w" "$IMG" \
  bash -c 'pip install -q kafka-python==3.0.11 confluent-kafka==2.15.1 >/dev/null 2>&1
    python /w/verify_consumer_group2.py' 2>&1 \
  | grep -v -e 'rdkafka#' -e 'Unclosed' -e '%7|'
