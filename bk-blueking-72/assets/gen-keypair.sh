#!/usr/bin/env bash
# 用途：用官方脚本生成 RSA keypair，补齐最后一个前置，然后渲染验证
set -uo pipefail
B=/root/bk72/install/blueking
E=$B/environments/default
BIN=/root/bk72/tools/bin
export PATH="$BIN:$PATH"

echo "===== 1. 生成 bkapigateway_builtin_keypair.yaml ====="
cd "$E" || exit 1
timeout 180 bash "$B/scripts/generate_rsa_keypair.sh" "$E/bkapigateway_builtin_keypair.yaml" 2>&1 | tail -12

echo ""
echo "===== 2. 检查生成结果 ====="
if [ -f "$E/bkapigateway_builtin_keypair.yaml" ]; then
  echo "★ 已生成"
  grep -cE '^  [a-z-]+:' "$E/bkapigateway_builtin_keypair.yaml" | xargs echo "网关条目数:"
  head -8 "$E/bkapigateway_builtin_keypair.yaml" | cut -c1-100
else
  echo "✗ 未生成"; exit 1
fi

echo ""
echo "===== 3. 前置齐备状态 ====="
for f in values.yaml version.yaml app_secret.yaml bkapigateway_builtin_keypair.yaml; do
  [ -f "$E/$f" ] && echo "  [有] $f" || echo "  [缺] $f"
done
