#!/usr/bin/env bash
# 用途：走官方路径——用 setup_bkce7.sh 生成 app_secret 等前置文件，再渲染验证
set -uo pipefail
B=/root/bk72/install/blueking
E=$B/environments/default
S=$B/scripts/setup_bkce7.sh
OUT=/root/bk72/render_test

echo "===== 1. 查看 setup 脚本用法（看有哪些子命令）====="
timeout 60 bash "$S" --help 2>&1 | head -40

echo ""
echo "===== 2. 是否有生成 app_secret 的独立脚本 ====="
ls -1 "$B"/scripts/ 2>/dev/null | head -30

echo ""
echo "===== 3. 查 appSecret 由谁生成 ====="
grep -rln 'appSecret\|app_secret' "$B"/scripts/ 2>/dev/null | head -5
