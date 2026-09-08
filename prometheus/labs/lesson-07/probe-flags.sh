#!/usr/bin/env bash
echo "=== agent 相关 flag ==="
docker run --rm prom/prometheus:v3.14.0 --help 2>&1 | grep -iE "agent|enable-feature" | head -20
echo
echo "=== remote 相关 flag ==="
docker run --rm prom/prometheus:v3.14.0 --help 2>&1 | grep -iE "remote|wal|shard|queue" | head -40
