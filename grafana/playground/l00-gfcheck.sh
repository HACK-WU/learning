#!/usr/bin/env bash
# 排障：Grafana 在 3001 上到底怎么了
set -u
echo "=== 1. 容器状态 ==="
docker ps -a --filter name=grafana-lab --format '{{.Names}} :: {{.Status}} :: {{.Ports}}'

echo "=== 2. health 原始响应 ==="
curl -s -i http://localhost:3001/api/health 2>&1 | head -15

echo "=== 3. 容器日志末尾 25 行 ==="
docker logs grafana-lab 2>&1 | tail -25

echo "=== 4. 端口是不是被别的容器抢了 ==="
docker ps --format '{{.Names}} :: {{.Ports}}' | grep -E '0.0.0.0:3001'
