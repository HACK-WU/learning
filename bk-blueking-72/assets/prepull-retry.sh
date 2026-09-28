#!/usr/bin/env bash
# 针对2个顽固镜像：逐个 layer 重试（失败通常是某个大 layer 被掐）
for img in \
  "bk-lite.tencentcloudcr.com/bklite/bklite/fusion-collector:latest" \
  "bk-lite.tencentcloudcr.com/bklite/bklite/webhookd:latest"; do
  echo "=== $img ==="
  for attempt in $(seq 1 5); do
    if timeout 400 docker pull "$img" >/dev/null 2>&1; then
      echo "  OK (第${attempt}次) $(date '+%H:%M:%S')"
      break
    else
      echo "  第${attempt}次失败 $(date '+%H:%M:%S')"
      sleep 5
    fi
  done
done
echo "=== 最终 bk-lite 镜像数: $(docker images --format '{{.Repository}}' | grep -c bk-lite) ==="
docker images --format '{{.Repository}}:{{.Tag}}' | grep bk-lite | sort
