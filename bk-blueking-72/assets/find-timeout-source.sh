#!/usr/bin/env bash
# 定位 600s timeout 的真实来源
set -uo pipefail
B=/root/bk72/install/blueking
export PATH=/root/bk72/install/bin:$PATH

echo "===== 1. helmfile 配置里的 timeout（defaults.yaml / base-blueking）====="
grep -rnE 'timeout|Timeout' "$B/defaults.yaml" "$B/base-blueking.yaml.gotmpl" "$B/base.yaml.gotmpl" 2>/dev/null | head -10

echo ""
echo "===== 2. helmDefaults 段全文 ====="
sed -n '/^helmDefaults:/,/^[a-z]/p' "$B/defaults.yaml" 2>/dev/null | head -12

echo ""
echo "===== 3. 环境变量 HELM_TIMEOUT ====="
echo "  HELM_TIMEOUT=${HELM_TIMEOUT:-未设置}"
helm env 2>/dev/null | grep -i timeout

echo ""
echo "===== 4. 安装脚本/文档中是否有 timeout 约定 ====="
grep -rnE '\-\-timeout' /root/bk72/install/*.sh /root/bk72/install/bin/*.sh 2>/dev/null | head -5

echo ""
echo "===== 5. 关键：helm 默认 timeout 是多少（源码级事实）====="
helm upgrade --help 2>&1 | grep -A2 -- '--timeout' | head -6

echo ""
echo "===== 6. 验证：不加任何 timeout 时 helm 实际用多久 ====="
echo "  （上面 --help 的 default 值即为答案）"
