#!/usr/bin/env bash
# 添加 blueking chart repo（已授权）
# 地址来源：environments/default/bcs/values.yaml.gotmpl:178
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH

echo "===== 1. 添加前 repo 列表 ====="
helm repo list 2>&1

echo ""
echo "===== 2. 执行 helm repo add blueking ====="
helm repo add blueking https://hub.bktencent.com/chartrepo/blueking 2>&1
echo "  退出码: $?"

echo ""
echo "===== 3. 更新 repo 索引 ====="
helm repo update blueking 2>&1
echo "  退出码: $?"

echo ""
echo "===== 4. 添加后验证：能否搜到所需 chart ====="
helm search repo blueking/bkrepo --versions 2>&1 | head -3
helm search repo blueking/bkauth --versions 2>&1 | head -3
helm search repo blueking/bk-apigateway --versions 2>&1 | head -3

echo ""
echo "===== 5. 最终 repo 列表 ====="
helm repo list 2>&1
