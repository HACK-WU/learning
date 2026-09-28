#!/usr/bin/env bash
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH

echo "===== 1. helm repo list ====="
helm repo list 2>&1

echo ""
echo "===== 2. helm 配置目录 ====="
echo "  HELM_REPOSITORY_CONFIG: ${HELM_REPOSITORY_CONFIG:-未设置}"
ls -la /root/.config/helm/ 2>/dev/null | head -10
cat /root/.config/helm/repositories.yaml 2>/dev/null | head -20

echo ""
echo "===== 3. 找 chart 目录（蓝鲸本地 chart）====="
ls /root/bk72/install/blueking/charts/ 2>/dev/null | head -20

echo ""
echo "===== 4. charts 里是否有 bkrepo/bkauth/apigateway ====="
ls /root/bk72/install/blueking/charts/ 2>/dev/null | grep -iE 'repo|auth|apigw'

echo ""
echo "===== 5. 之前 base-storage 用的 chart 来源 ====="
grep -n 'chart' /root/bk72/install/blueking/base-storage.yaml.gotmpl 2>/dev/null | head -10
