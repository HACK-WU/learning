#!/bin/bash
set -u
NET=stage6-observability_kafka-net
W=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
docker run --rm --network "$NET" -v "$W:/w" python:3.12-slim \
  bash -c 'pip install -q kafka-python==3.0.11 >/dev/null 2>&1
    python /w/verify_acks_retry.py' 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed'
