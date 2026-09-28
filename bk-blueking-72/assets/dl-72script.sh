#!/usr/bin/env bash
# 用途：验证 7.2 官方下载脚本 bkdl-7.2-stable.sh 可获取性
# 来源：官方升级文档 https://bk.tencent.com/docs/markdown/ZH/DeploymentGuides/7.2/upgrade-from-v71.md
set -uo pipefail

echo "===== 1. 下载官方 7.2 部署脚本 ====="
mkdir -p /root/bk72/bin
timeout 60 curl -sSf "https://bkopen-1252002024.file.myqcloud.com/ce7/7.2-stable/bkdl-7.2-stable.sh" \
  -o /root/bk72/bin/bkdl-7.2-stable.sh 2>&1
if [ -s /root/bk72/bin/bkdl-7.2-stable.sh ]; then
  echo "下载 OK, 大小: $(stat -c%s /root/bk72/bin/bkdl-7.2-stable.sh) 字节"
else
  echo "下载失败"
  exit 1
fi

echo ""
echo "===== 2. 脚本头部（确认来源与版本）====="
head -30 /root/bk72/bin/bkdl-7.2-stable.sh

echo ""
echo "===== 3. 脚本里用到的下载地址 ====="
grep -oE 'https?://[a-zA-Z0-9./_:-]+' /root/bk72/bin/bkdl-7.2-stable.sh 2>/dev/null | sort -u | head -15
