#!/usr/bin/env bash
set -uo pipefail
echo "===== bk-config 目录结构 ====="
ls -la /root/bk72/install/bk-config/ 2>&1 | head -30

echo ""
echo "===== 是否有证书相关目录 ====="
ls -la /root/bk72/install/bk-config/cert 2>/dev/null || echo "(无 cert 目录)"

echo ""
echo "===== 关键配置文件 ====="
ls /root/bk72/install/bk-config/*.yaml /root/bk72/install/bk-config/*.env 2>/dev/null | head -10
