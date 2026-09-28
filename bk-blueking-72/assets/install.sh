#!/usr/bin/env bash
set -uo pipefail

export HOST_IP=$(hostname -I | awk '{print $1}')
export TRAEFIK_WEB_PORT=8080

LOG=/tmp/bk-lite-install2.log
: > "$LOG"

{
  echo "HOST_IP=$HOST_IP"
  echo "TRAEFIK_WEB_PORT=$TRAEFIK_WEB_PORT"
  echo "开始: $(date '+%F %T')"
  echo "已预拉镜像数: $(docker images --format '{{.Repository}}' | grep -c bk-lite)"
  echo "=========================================="
} | tee -a "$LOG"

cd /tmp/bklite-src
bash ./bootstrap.sh >> "$LOG" 2>&1
RC=$?

echo "==========================================" | tee -a "$LOG"
echo "BOOTSTRAP_EXIT=$RC" | tee -a "$LOG"
echo "结束: $(date '+%F %T')" | tee -a "$LOG"
echo "--- 最后 30 行 ---"
tail -30 "$LOG"
