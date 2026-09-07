#!/usr/bin/env bash
# 端口占用排查：看宿主上哪些端口已被容器映射，给 Grafana 课程挑空闲端口
set -u
echo "=== 1. 当前所有容器及其宿主端口映射 ==="
docker ps --format '{{.Names}} :: {{.Ports}}'

echo
echo "=== 2. Grafana 课程关心的端口是否被占 ==="
for p in 3001 3002 9091 9092 9093 9101 3101 16687; do
  HIT=$(docker ps --format '{{.Ports}}' | grep -oE "0\.0\.0\.0:${p}->" | head -1)
  if [ -n "$HIT" ]; then
    OWNER=$(docker ps --format '{{.Names}} :: {{.Ports}}' | grep "0.0.0.0:${p}->")
    echo "  端口 $p 已占用 -> $OWNER"
  else
    echo "  端口 $p 空闲"
  fi
done
