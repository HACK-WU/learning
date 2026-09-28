#!/usr/bin/env bash
# 用途：验证 bk-config-combo 全局配置包能否真实下载（最小成本验证制品可达性）
set -uo pipefail
S=/root/bk72/bin/bkdl-7.2-stable.sh

echo "===== 下载最小制品 bk-config-combo（仅配置，体积小）====="
timeout 180 bash "$S" -r 7.2.19 -i /root/bk72/install bk-config-combo 2>&1 | tail -20

echo ""
echo "===== 结果 ====="
ls -la /root/bk72/install/ 2>/dev/null | head -15
