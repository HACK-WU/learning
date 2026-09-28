#!/usr/bin/env bash
# 用途：下载官方「chart-images」镜像总表，拿到自研组件的真实镜像名，再实测
set -uo pipefail
S=/root/bk72/bin/bkdl-7.2-stable.sh
DL=/root/bk72/chart-images
mkdir -p "$DL"

echo "===== 1. 下载官方镜像总表 chart-images ====="
timeout 600 bash "$S" -r 7.2.19 -i "$DL" chart-images 2>&1 | tail -8

echo ""
echo "===== 2. 定位镜像清单文件 ====="
F=$(find "$DL" -type f \( -name '*.txt' -o -name '*.yaml' -o -name '*.json' -o -name '*.list' \) 2>/dev/null | head -5)
echo "候选文件: $F"

echo ""
echo "===== 3. 查看清单内容样例 ====="
for f in $F; do
  echo "--- $(basename "$f") ($(wc -l < "$f") 行) ---"
  head -8 "$f"
  break
done
