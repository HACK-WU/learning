#!/usr/bin/env bash
# 用途：前置齐备后，真渲染 GSE 模板，验证证书注入
set -uo pipefail
E=/root/bk72/install/blueking/environments/default
BIN=/root/bk72/tools/bin
HF=$BIN/helmfile
OUT=/root/bk72/render_test
export PATH="$BIN:$PATH"

rm -rf /tmp/probe5; mkdir -p /tmp/probe5/templates
cat > /tmp/probe5/Chart.yaml <<'EOF'
apiVersion: v2
name: probe5
version: 0.1.0
EOF
: > /tmp/probe5/values.yaml
cat > /tmp/probe5/templates/dump.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: values-dump
data:
  all: |
{{ toYaml .Values | indent 4 }}
EOF

PROBE="$E/zz_p5.yaml.gotmpl"
cat > "$PROBE" <<'EOF'
environments:
  default:
    values:
      - values.yaml
      - version.yaml
      - app_secret.yaml
---
releases:
  - name: probe5
    chart: /tmp/probe5
    values:
      - bkgse-ce-values.yaml.gotmpl
EOF

cd "$E" || exit 1
echo "===== 真渲染 GSE ====="
timeout 180 "$HF" -f zz_p5.yaml.gotmpl template > "$OUT/p5.log" 2>&1
rc=$?
echo "退出码: $rc"; echo "字节: $(wc -c < "$OUT/p5.log")"

if [ $rc -ne 0 ]; then
  echo "✗ 失败:"; grep -iE 'error|failed|no such file|no entry' "$OUT/p5.log" | head -6
  rm -f "$PROBE"; exit 1
fi

echo ""
echo "===== 证书注入判定 ====="
grep -qE 'LS0t|BEGIN CERT' "$OUT/p5.log" && echo "★★★ 证书已真实注入" || echo "? 未见证书"

echo ""
echo "===== ca/cert/key 字段（前90字符）====="
grep -nE '^\s+(ca|cert|key):' "$OUT/p5.log" | head -6 | cut -c1-90

echo ""
echo "===== 规模 ====="
echo "总行数: $(wc -l < "$OUT/p5.log")"

rm -f "$PROBE"; echo "已清理"
