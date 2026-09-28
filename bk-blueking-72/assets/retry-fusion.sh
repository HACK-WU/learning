#!/usr/bin/env bash
IMG="bk-lite.tencentcloudcr.com/bklite/bklite/fusion-collector:latest"

for attempt in $(seq 1 10); do
  echo "[$(date '+%H:%M:%S')] 第${attempt}次尝试..."
  if timeout 500 docker pull "$IMG" >/tmp/fusion-attempt.log 2>&1; then
    echo "OK! 第${attempt}次成功"
    docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | grep fusion
    exit 0
  else
    tail -1 /tmp/fusion-attempt.log
    sleep 20
  fi
done
echo "10次均失败，镜像拉取确实存在稳定阻断"
