#!/usr/bin/env bash
set -uo pipefail

echo "===== 1. 定位官方 bk-lite chart 目录 ====="
for d in /root/bk-lite /opt/bk-lite /data/bk-lite /mnt/d/projects/learning/bk-blueking-72 $HOME/bk-lite; do
  if [ -d "$d/charts" ]; then echo "  找到: $d/charts"; ls -1 "$d/charts" | sed 's/^/    /'; fi
done

echo ""
echo "===== 2. 全局搜 chart 目录（限深，避免全盘扫）====="
find /root /opt /data /home /mnt/d/projects -maxdepth 4 -type d \( -name "charts" -o -name "bk-lite*" \) 2>/dev/null | head -20 | sed 's/^/  /'

echo ""
echo "===== 3. 搜 nodeman / monitor 相关 chart 包 ====="
find /root /opt /data /home /mnt/d/projects -maxdepth 5 \( -name "bk-nodeman*" -o -name "bk-monitor*" -o -name "*nodeman*" \) 2>/dev/null | head -15 | sed 's/^/  /'

echo ""
echo "===== 4. helm repo 里有哪些可用 chart（看能装什么）====="
helm search repo 2>/dev/null | head -40 | sed 's/^/  /'

echo ""
echo "===== 5. helm repo 列表 ====="
helm repo list 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 6. 本地 chart 缓存（~/.cache/helm）====="
ls -1 ~/.cache/helm/repository 2>/dev/null | head -30 | sed 's/^/  /'
