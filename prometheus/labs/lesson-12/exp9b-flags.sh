#!/usr/bin/env bash
echo "===== 3.14.0 所有 storage.tsdb.* flag ====="
docker run --rm prom/prometheus:v3.14.0 --help 2>&1 | grep -A2 "storage.tsdb" | grep "storage.tsdb" | sed 's/^ *//' | head -40

echo
echo "===== 是否还有全局 series/sample 限制类 flag ====="
docker run --rm prom/prometheus:v3.14.0 --help 2>&1 | grep -iE "limit|max-" | sed 's/^ *//' | head -20
