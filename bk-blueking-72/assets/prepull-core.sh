#!/usr/bin/env bash
# 补齐缺失的核心自研镜像（server / web / stargazer / nats-executor）
BASE="bk-lite.tencentcloudcr.com/bklite/bklite"
for svc in server web stargazer nats-executor; do
  img="$BASE/$svc:latest"
  echo "=== $img ==="
  for attempt in $(seq 1 8); do
    if timeout 500 docker pull "$img" >/tmp/pull-$svc.log 2>&1; then
      echo "  OK (第${attempt}次) $(date '+%H:%M:%S')"
      break
    else
      echo "  第${attempt}次失败 $(date '+%H:%M:%S')"
      sleep 15
    fi
  done
done
echo "=== 最终 bk-lite 镜像数: $(docker images --format '{{.Repository}}' | grep -c bk-lite) ==="
