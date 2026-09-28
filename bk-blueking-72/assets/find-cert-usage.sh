#!/usr/bin/env bash
# 用途：在 bkhelmfile 部署体系中定位证书落位（全量搜索）
set -uo pipefail
B=/root/bk72/install/blueking

echo "===== 1. 部署目录结构 ====="
ls -la "$B/" 2>&1 | head -20

echo ""
echo "===== 2. 搜索证书文件名引用（gse_server/platform/license 等）====="
grep -rln --include='*.yaml' --include='*.yaml.tpl' --include='*.gotmpl' --include='*.sh' --include='*.tpl' \
  -E 'gse_server|gseca|platform\.cert|license_cert|job_server\.p12|gse_agent\.crt' "$B" 2>/dev/null | head -20

echo ""
echo "===== 3. 是否有 cert 目录或示例证书 ====="
find "$B" -maxdepth 4 -type d \( -iname '*cert*' -o -iname '*ssl*' \) 2>/dev/null | head -10

echo ""
echo "===== 4. 顶层 helmfile ====="
ls "$B"/*.yaml "$B"/*.gotmpl 2>/dev/null | head -10
