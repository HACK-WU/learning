#!/usr/bin/env bash
# 用途：下载 bkhelmfile（7.2 核心部署文件）并探查证书落位
set -uo pipefail
S=/root/bk72/bin/bkdl-7.2-stable.sh

echo "===== 下载 bkhelmfile 7.2.19 ====="
timeout 300 bash "$S" -r 7.2.19 -i /root/bk72/install bkhelmfile 2>&1 | grep -vE '^\s*[#%]|%$' | tail -10

echo ""
echo "===== 安装目录结构 ====="
ls -la /root/bk72/install/ 2>&1 | head -20

echo ""
echo "===== 证书/secrets 相关文件 ====="
find /root/bk72/install -maxdepth 3 \( -iname '*cert*' -o -iname '*secret*' -o -iname '*gse*' \) 2>/dev/null | head -20
