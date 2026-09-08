#!/usr/bin/env bash
# 探测 v3.14.0 可用的状态端点
for p in api/v1/status/build_info api/v1/status/runtimeinfo api/v1/status/tsdb; do
  echo "== $p =="
  docker exec l6-prom wget -qO- "http://localhost:9090/$p" 2>&1 | head -c 250
  echo
done

echo "== targets =="
docker exec l6-prom wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>&1 | head -c 600
echo
