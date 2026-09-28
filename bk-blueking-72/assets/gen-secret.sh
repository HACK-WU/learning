#!/usr/bin/env bash
# 用途：1) 补 helmfile 到官方期望路径 2) 生成 app_secret 3) 重新渲染验证
set -uo pipefail
B=/root/bk72/install/blueking
E=$B/environments/default
HF=/root/bk72/tools/bin/helmfile
OUT=/root/bk72/render_test

echo "===== 1. 补 helmfile 到官方期望路径 ../../bin/ ====="
mkdir -p "$B/../bin" 2>/dev/null
ln -sf "$HF" "$B/../bin/helmfile" 2>/dev/null
ls -l "$B/../bin/helmfile" 2>&1 | head -2
echo "验证: $("$B/../bin/helmfile" version 2>&1 | head -1)"

echo ""
echo "===== 2. 查看 generate_app_secret.sh 用法 ====="
timeout 60 bash "$B/scripts/generate_app_secret.sh" --help 2>&1 | head -25

echo ""
echo "===== 3. 执行生成 app_secret ====="
cd "$E" || exit 1
timeout 120 bash "$B/scripts/generate_app_secret.sh" 2>&1 | tail -10

echo ""
echo "===== 4. 检查生成结果 ====="
ls -l "$E"/app_secret.yaml 2>&1 | head -2
[ -f "$E/app_secret.yaml" ] && head -8 "$E/app_secret.yaml"
