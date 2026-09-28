#!/usr/bin/env bash
# 用途：核验渲染结果是否真实展开（防止"渲染成功"是假阳性）
set -uo pipefail
B=/root/bk72/install/blueking
E=$B/environments/default
HF=/root/bk72/tools/bin/helmfile
OUT=/root/bk72/render_test

echo "===== 1. 上一次渲染输出内容（看是否真展开）====="
head -40 "$OUT/render.log"

echo ""
echo "===== 2. 单独渲染 GSE 模板（证书核心引用方）====="
PROBE="$E/zz_gse_probe.yaml.gotmpl"
cat > "$PROBE" <<'EOF'
bases:
  - ../../env.yaml
  - ../../defaults.yaml
---
releases:
  - name: gse-probe
    chart: /tmp/probe-chart
    values:
      - bkgse-ce-values.yaml.gotmpl
EOF
cd "$E" || exit 1
timeout 120 "$HF" -f zz_gse_probe.yaml.gotmpl build > "$OUT/gse.log" 2>&1
echo "退出码: $?"
echo "输出字节: $(wc -c < "$OUT/gse.log")"

echo ""
echo "===== 3. GSE 渲染输出中是否含 base64 证书（验证 readFile 真生效）====="
if grep -qE 'gseca|gse_server|CA==|LS0t' "$OUT/gse.log"; then
  echo "★ 检测到证书内容，readFile 真实生效"
  grep -oE '[A-Za-z0-9+/]{60,}' "$OUT/gse.log" | head -2 | cut -c1-80
else
  echo "✗ 未见证书内容"
fi

echo ""
echo "===== 4. 直接看 bkgse-ce-values 模板里证书引用的原始写法 ====="
grep -nE 'readFile|cert/' "$E/bkgse-ce-values.yaml.gotmpl" | head -12

echo ""
echo "===== 5. 清理 ====="
rm -f "$PROBE"; echo "已清理探针"
