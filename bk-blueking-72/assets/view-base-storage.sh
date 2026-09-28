#!/usr/bin/env bash
# 用途：看清 base-storage 批次的确切 release 清单
set -uo pipefail
B=/root/bk72/install/blueking

echo "===== 1. base-storage.yaml.gotmpl ====="
cat "$B/base-storage.yaml.gotmpl"

echo ""
echo "===== 2. base.yaml.gotmpl ====="
cat "$B/base.yaml.gotmpl"

echo ""
echo "===== 3. 所有顶层 helmfile 入口 ====="
ls -la "$B"/*.yaml* 2>/dev/null | head -20
