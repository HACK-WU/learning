#!/usr/bin/env bash
set -uo pipefail
F=/root/bk72/install/blueking/environments/default/bkgse-ce-values.yaml.gotmpl

echo "===== bkgse-ce-values.yaml.gotmpl 中证书相关段 ====="
grep -nE 'gse_server|gseca|gse_agent|cert|key|p12|\.crt|base64|\.Files|readFile' "$F" 2>/dev/null | head -40

echo ""
echo "===== 文件总行数 ====="
wc -l "$F"
