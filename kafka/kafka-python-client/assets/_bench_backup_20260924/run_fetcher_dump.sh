#!/bin/bash
set -u
W=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
docker run --rm -v "$W:/w" python:3.12-slim \
  bash -c 'pip install -q kafka-python==3.0.11 >/dev/null 2>&1
    python /w/dump_fetcher.py' 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed'
