#!/usr/bin/env bash
# 用途：列出 7.2 可用版本与制品清单（干跑，不下载任何制品）
set -uo pipefail
S=/root/bk72/bin/bkdl-7.2-stable.sh

echo "===== 1. 可用版本列表 ====="
timeout 60 bash "$S" -r list 2>&1 | tail -20

echo ""
echo "===== 2. 取 latest 版本 ====="
LATEST=$(timeout 60 bash "$S" -r list 2>/dev/null | tail -1 | tr -d '[:space:]')
echo "latest = [$LATEST]"

echo ""
echo "===== 3. 该版本的制品清单（干跑 -nn，不下载）====="
if [ -n "$LATEST" ]; then
  timeout 90 bash "$S" -r "$LATEST" -nn 2>&1 | head -60
fi
