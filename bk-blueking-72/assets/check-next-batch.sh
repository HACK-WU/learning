#!/usr/bin/env bash
set -uo pipefail
B=/root/bk72/install/blueking

echo "===== 1. helmfile 主入口 ====="
ls -la "$B"/*.yaml.gotmpl 2>/dev/null | head -5
echo "--- 是否有 helmfile.yaml ---"
ls "$B"/ | grep -i helmfile

echo ""
echo "===== 2. base.yaml.gotmpl 内容（批次 0）====="
cat "$B/base.yaml.gotmpl" 2>/dev/null | head -40

echo ""
echo "===== 3. base-blueking.yaml.gotmpl（批次 next？）====="
cat "$B/base-blueking.yaml.gotmpl" 2>/dev/null | head -40

echo ""
echo "===== 4. 查找 seq/first 标记 ====="
grep -rn 'seq:\|first\|selector' "$B"/*.yaml.gotmpl 2>/dev/null | head -20

echo ""
echo "===== 5. 已有 release 清单（判断进度）====="
helm list -n blueking --no-headers 2>/dev/null | awk '{print "  "$1"  "$8}'
