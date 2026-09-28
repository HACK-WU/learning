#!/usr/bin/env bash
echo "=== 1. 本地已有 bk-lite 镜像 ==="
docker images --format '{{.Repository}}:{{.Tag}}' | grep bk-lite | sort

echo ""
echo "=== 2. 日志中本次涉及的镜像 (去重) ==="
grep -ohE 'bk-lite\.tencentcloudcr\.com/[a-z0-9._/-]+:[a-zA-Z0-9._-]+' /tmp/bk-lite-install2.log | sort -u

echo ""
echo "=== 3. 日志中 Pulling 的镜像顺序 ==="
grep -E 'Pulling|pulling' /tmp/bk-lite-install2.log | head -20

echo ""
echo "=== 4. server/web/stargazer 等自研镜像是否在本地 ==="
for s in server web stargazer mlflow nats-executor controller; do
  c=$(docker images --format '{{.Repository}}' | grep -c "bklite/$s")
  echo "$s: $c"
done
