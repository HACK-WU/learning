#!/usr/bin/env bash
set -u
PORT=7102
PY=/mnt/d/projects/learning/redis/playground
mkdir -p /tmp/redis-l08
echo "===== samples 差异定位 ====="
cd /tmp && python3 "$PY/prep-lesson-08-samples-probe.py" 2>&1
echo
redis-cli -p $PORT shutdown nosave 2>/dev/null || true
echo "done"
