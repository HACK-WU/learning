#!/usr/bin/env bash
# 排查：为什么 -v 挂载后 promtool 认为是目录？
cd /d/projects/learning/prometheus || exit 1
L7="$(pwd)/labs/lesson-07"
echo "L7 = $L7"
echo "文件内容前 3 行："
head -n 3 "$L7/prometheus.yml"
echo
echo "--- 方式1：用 \$L7 变量 ---"
docker run --rm -v "$L7/prometheus.yml:/tmp/c.yml:ro" \
  --entrypoint /bin/promtool prom/prometheus:v3.14.0 \
  check config /tmp/c.yml 2>&1 | tail -n 3
echo
echo "--- 方式2：容器内看 /tmp/c.yml 是什么 ---"
docker run --rm -v "$L7/prometheus.yml:/tmp/c.yml:ro" \
  --entrypoint sh prom/prometheus:v3.14.0 \
  -c 'ls -la /tmp/c.yml; file /tmp/c.yml 2>/dev/null; head -n 2 /tmp/c.yml' 2>&1 | tail -n 6
echo
echo "--- 方式3：改用 /etc/prometheus/ 路径 ---"
docker run --rm -v "$L7/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
  --entrypoint /bin/promtool prom/prometheus:v3.14.0 \
  check config /etc/prometheus/prometheus.yml 2>&1 | tail -n 3
