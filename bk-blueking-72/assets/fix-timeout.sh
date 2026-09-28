#!/usr/bin/env bash
# 修改 helmfile timeout（先备份）
set -uo pipefail
B=/root/bk72/install/blueking
TS=$(date +%Y%m%d-%H%M%S)

echo "===== 备份 ====="
cp "$B/defaults.yaml" "$B/defaults.yaml.bak-$TS" && echo "  defaults.yaml -> defaults.yaml.bak-$TS"
cp "$B/base-blueking.yaml.gotmpl" "$B/base-blueking.yaml.gotmpl.bak-$TS" && echo "  base-blueking.yaml.gotmpl -> .bak-$TS"

echo ""
echo "===== 修改前 ====="
grep -n 'timeout' "$B/defaults.yaml" "$B/base-blueking.yaml.gotmpl"

echo ""
echo "===== 执行修改 ====="
# 1. 全局 600 -> 1800
sed -i 's/^  timeout: 600$/  timeout: 1800/' "$B/defaults.yaml"
# 2. release 级 900 -> 1800
sed -i 's/^    timeout: 900$/    timeout: 1800/' "$B/base-blueking.yaml.gotmpl"

echo ""
echo "===== 修改后 ====="
grep -n 'timeout' "$B/defaults.yaml" "$B/base-blueking.yaml.gotmpl"

echo ""
echo "===== 校验 YAML 语法（gotmpl 用 helmfile 渲染验证）====="
export PATH=/root/bk72/install/bin:$PATH
cd "$B" && /root/bk72/install/bin/helmfile -f base-blueking.yaml.gotmpl -l seq=first list 2>&1 | tail -6
