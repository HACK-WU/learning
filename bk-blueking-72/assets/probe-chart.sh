#!/usr/bin/env bash
echo "=== 1. blueking helm repo 内容 (前20个 chart) ==="
timeout 30 curl -sS -k "https://hub.bktencent.com/chartrepo/blueking/index.yaml" 2>&1 \
  | grep -E '^  [a-z0-9-]+:' | head -20

echo ""
echo "=== 2. chart 总数 ==="
timeout 30 curl -sS -k "https://hub.bktencent.com/chartrepo/blueking/index.yaml" 2>&1 \
  | grep -cE '^  [a-z0-9-]+:'

echo ""
echo "=== 3. 关键组件 chart 版本 ==="
timeout 30 curl -sS -k "https://hub.bktencent.com/chartrepo/blueking/index.yaml" 2>&1 \
  | grep -A2 -E '^  (bk-cmdb|bk-job|bk-paas3|bk-user|bk-iam|bk-nodeman|bk-sops|bk-apigateway):' | head -30
