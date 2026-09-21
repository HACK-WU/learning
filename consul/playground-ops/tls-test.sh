#!/usr/bin/env bash
set -euo pipefail
BASE=/tmp/consul-ops
cd "$BASE"

echo "===== 自签 CA（consul tls 子命令）====="
consul tls ca create -domain=consul 2>&1 | tail -3
ls -1 *.pem 2>/dev/null

echo
echo "===== 签发 server 证书 ====="
consul tls cert create -server -dc=opsdc1 2>&1 | tail -3
ls -1 *.pem

echo
echo "===== 证书有效期（运维要盯的）====="
for f in *.pem; do
  openssl x509 -in "$f" -noout -subject -enddate 2>/dev/null && echo "  ^ $f" || true
done
