#!/usr/bin/env bash
echo "===== check healthy 用法 ====="
docker run --rm --entrypoint promtool prom/prometheus:v3.14.0 check healthy --help 2>&1 | head -20
echo
echo "===== check ready 用法 ====="
docker run --rm --entrypoint promtool prom/prometheus:v3.14.0 check ready --help 2>&1 | head -20
