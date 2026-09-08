#!/usr/bin/env bash
set -uo pipefail
NET=l9net

echo "=== querier 日志（store 发现相关）==="
docker logs l9-thanos-query 2>&1 | grep -iE 'endpoint|store|sd|error|warn' | tail -15
echo
echo "=== querier 是否读到 sd 文件 ==="
docker exec l9-thanos-query sh -c 'cat /etc/thanos/sd/stores.yaml' 2>&1 | head -5
echo
echo "=== 直连 sidecar gRPC 端口是否通 ==="
for h in l9-thanos-sc-1 l9-thanos-sc-2 l9-thanos-store; do
  printf '%-20s ' "$h:19090"
  docker run --rm --network $NET --entrypoint sh curlimages/curl:latest -c \
    "timeout 3 sh -c 'echo > /dev/tcp/$h/19090' 2>/dev/null && echo OPEN || echo CLOSED"
done
echo
echo "=== 等一会再看 stores ==="
sleep 20
docker run --rm --network $NET curlimages/curl:latest -s \
  http://l9-thanos-query:19191/api/v1/stores 2>/dev/null | head -c 900
echo
