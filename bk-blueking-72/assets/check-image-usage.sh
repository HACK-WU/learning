#!/usr/bin/env bash
# 用途：查看官方镜像检测脚本用法
set -uo pipefail
B=/root/bk72/install/blueking

echo "===== 1. check_image_exists.sh 用法 ====="
timeout 60 bash "$B/scripts/check_image_exists.sh" --help 2>&1 | head -30

echo ""
echo "===== 2. 脚本源码前 60 行 ====="
head -60 "$B/scripts/check_image_exists.sh"

echo ""
echo "===== 3. list_all_image.sh 用法（列出全部镜像）====="
head -40 "$B/scripts/list_all_image.sh"
