#!/usr/bin/env bash
# 用途：列出 setup_bkce7.sh 生成的所有前置配置文件（一次性补齐）
set -uo pipefail
S=/root/bk72/install/blueking/scripts/setup_bkce7.sh
E=/root/bk72/install/blueking/environments/default

echo "===== 1. setup 脚本里生成/写入 environments 下文件的函数 ====="
grep -nE '_config_[a-z_]+|generate_.*\.sh|_generate' "$S" | head -40

echo ""
echo "===== 2. 当前 default 目录已有 vs 缺失 ====="
for f in values.yaml version.yaml app_secret.yaml custom.yaml bkapigateway_builtin_keypair.yaml; do
  [ -f "$E/$f" ] && echo "  [有] $f" || echo "  [缺] $f"
done

echo ""
echo "===== 3. builtinGateway 由谁生成 ====="
grep -rn 'builtinGateway\|builtin_keypair\|generate_rsa_keypair' /root/bk72/install/blueking/scripts/*.sh 2>/dev/null | head -8

echo ""
echo "===== 4. generate_rsa_keypair.sh 用法 ====="
head -30 /root/bk72/install/blueking/scripts/generate_rsa_keypair.sh
