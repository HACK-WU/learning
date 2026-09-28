#!/usr/bin/env bash
# 排查 helmfile v0.142.0 selector 为何不生效
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH
HF=/root/bk72/install/bin/helmfile
B=/root/bk72/install/blueking
cd "$B" || exit 1

echo "===== 测试各版本 selector 语法（每组应只出 3 个）====="

echo "--- A: -l seq=first ---"
$HF -f base.yaml.gotmpl -l seq=first list 2>/dev/null | grep -c 'blueking' 

echo "--- B: --selector seq=first ---"
$HF -f base.yaml.gotmpl --selector seq=first list 2>/dev/null | grep -c 'blueking'

echo "--- C: 标准语法 -l seq=first（带引号）---"
$HF -f base.yaml.gotmpl -l 'seq=first' list 2>/dev/null | grep -c 'blueking'

echo "--- D: 直接对 base-blueking 用 selector ---"
$HF -f base-blueking.yaml.gotmpl -l seq=first list 2>/dev/null | grep -c 'blueking'

echo "--- E: base-blueking 不带 selector ---"
$HF -f base-blueking.yaml.gotmpl list 2>/dev/null | grep -c 'blueking'

echo ""
echo "===== 关键：D vs E 若相同，说明 selector 完全失效 ====="
echo "  D(first)=$($HF -f base-blueking.yaml.gotmpl -l seq=first list 2>/dev/null | grep -c blueking)"
echo "  E(all)  =$($HF -f base-blueking.yaml.gotmpl list 2>/dev/null | grep -c blueking)"

echo ""
echo "===== 另一种可能：selector 生效但 list 显示全部（apply 会过滤）====="
echo "对比 template 输出行数:"
echo "  带 selector : $($HF -f base.yaml.gotmpl -l seq=first template 2>/dev/null | wc -l)"
echo "  不带selector: $($HF -f base.yaml.gotmpl template 2>/dev/null | wc -l)"

echo ""
echo "===== helmfile 帮助里的 selector 说明 ====="
$HF list --help 2>&1 | grep -iA3 'selector' | head -12
