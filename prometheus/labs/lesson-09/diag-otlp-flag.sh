#!/usr/bin/env bash
set -uo pipefail
echo "=== 1. help 输出到 stdout 还是 stderr？==="
echo -n "  stdout: "; docker run --rm prom/prometheus:v3.14.0 --help 2>/dev/null | grep -c 'otlp'
echo -n "  stderr: "; docker run --rm prom/prometheus:v3.14.0 --help 2>&1 1>/dev/null | grep -c 'otlp'

echo
echo "=== 2. 直接看含 otlp 的行 ==="
docker run --rm prom/prometheus:v3.14.0 --help 2>&1 | grep -n 'otlp' | head -6

echo
echo "=== 3. 逐字确认 flag 名（hexdump 前 60 字符）==="
docker run --rm prom/prometheus:v3.14.0 --help 2>&1 | grep 'otlp-receiver' | head -2 | cat -A | head -4
