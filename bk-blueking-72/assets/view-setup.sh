#!/usr/bin/env bash
# 用途：查 setup_bkce7.sh 对证书/前置条件的校验逻辑
set -uo pipefail
S=/root/bk72/install/blueking/scripts/setup_bkce7.sh

echo "===== 1. 脚本规模 ====="
wc -l "$S"

echo ""
echo "===== 2. 是否有 cert 前置检查函数 ====="
grep -nE '_check.*cert|cert.*check|validate.*cert|cert_dir|CERT_DIR' "$S" | head -15

echo ""
echo "===== 3. 所有 _check_ 开头的校验项（看哪些是硬门槛）====="
grep -nE '^\s*_check_[a-z_]+\s*\(\)' "$S" | head -30

echo ""
echo "===== 4. 主流程调用顺序 ====="
grep -nE '^\s+_(check|config|install|deploy|render)[a-z_]*\s*$' "$S" | sed -n '1,40p'
