#!/usr/bin/env bash
set -uo pipefail
echo "===== 1. 全盘找 bkrepo / bkauth / apigateway 的 chart ====="
find /root/bk72 /root /opt /data -maxdepth 6 \( -name 'bkrepo*.tgz' -o -name 'bkauth*.tgz' -o -name 'apigateway*.tgz' -o -name 'bk-apigateway*.tgz' \) 2>/dev/null | head -15

echo ""
echo "===== 2. chart-images 目录（可能有镜像清单）====="
ls -la /root/bk72/chart-images/ 2>/dev/null | head -15

echo ""
echo "===== 3. 是否有 charts 压缩包/离线包 ====="
find /root/bk72 -maxdepth 3 -name '*.tar*' -o -maxdepth 3 -name '*.tgz' 2>/dev/null | head -10

echo ""
echo "===== 4. bkdl 脚本里是否定义了 repo 地址 ====="
grep -nE 'repo|hub\.bktencent|chart' /root/bk72/bin/bkdl-7.2-stable.sh 2>/dev/null | head -15

echo ""
echo "===== 5. 下载目录（是否有未解压的 chart 包）====="
find /root -maxdepth 4 -type d -name 'charts' 2>/dev/null | head -5
echo "--- 各 charts 目录内容数 ---"
for d in $(find /root -maxdepth 4 -type d -name 'charts' 2>/dev/null | head -5); do
  echo "  $d: $(ls $d 2>/dev/null | wc -l) 个"
done
