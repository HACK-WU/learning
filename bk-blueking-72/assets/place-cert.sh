#!/usr/bin/env bash
# 用途：将已校验的 ssl_certificates 解压到 helmfile 期望的 cert/ 目录并验证落位
# 幂等：可重复执行
set -uo pipefail

SRC_TAR="/mnt/d/projects/learning/bk-blueking-72/assets/ssl/ssl_certificates.tar.gz"
CERT_DIR="/root/bk72/install/blueking/environments/default/cert"

install -d -m 755 "$CERT_DIR"
tar -xzf "$SRC_TAR" -C "$CERT_DIR" 2>&1 || { echo "解压失败"; exit 1; }
chmod 644 "$CERT_DIR"/* 2>/dev/null

echo "===== 1. cert 目录内容 ====="
ls -l "$CERT_DIR" | head -25

echo ""
echo "===== 2. 验证模板 readFile 引用的 7 个文件都存在 ====="
for f in gseca.crt gse_server.crt gse_server.key gse_api_client.crt gse_api_client.key gse_agent.crt gse_agent.key; do
  if [ -s "$CERT_DIR/$f" ]; then
    echo "  [OK]   $f"
  else
    echo "  [缺失] $f"
  fi
done

echo ""
echo "===== 3. 模拟模板渲染：验证 base64 编码可正常生成 ====="
for f in gseca.crt gse_server.crt gse_server.key; do
  b64=$(base64 -w0 "$CERT_DIR/$f")
  echo "  $f -> base64 长度 ${#b64}"
done
