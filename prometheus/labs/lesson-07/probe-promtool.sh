#!/usr/bin/env bash
echo "=== promtool 在哪 ==="
docker run --rm --entrypoint sh prom/prometheus:v3.14.0 -c 'ls -la /bin/ /usr/bin/ 2>/dev/null | grep -iE "promtool|prometheus"'
echo
echo "=== 直接尝试常见路径 ==="
docker run --rm --entrypoint /bin/promtool prom/prometheus:v3.14.0 --version 2>&1 | tail -n 5
