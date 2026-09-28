#!/usr/bin/env bash
# 用途：前置全部齐备后，真渲染 GSE 模板，验证证书注入（决定性验证）
set -uo pipefail
E=/root/bk72/install/blueking/environments/default
BIN=/root/bk72/tools/bin
HF=$BIN/helmfile
OUT=/root/bk72/render_test
export PATH="$BIN:$PATH"

rm -rf /tmp/probe6; mkdir -p /tmp/probe6/templates
cat > /tmp/probe6/Chart.yaml <<'EOF'
apiVersion: v2
name: probe6
version: 0.1.0
EOF
: > /tmp/probe6/values.yaml
cat > /tmp/probe6/templates/dump.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: values-dump
data:
  all: |
{{ toYaml .Values | indent 4 }}
EOF

PROBE="$E/zz_p6.yaml.gotmpl"
cat > "$PROBE" <<'EOF'
environments:
  default:
    values:
      - values.yaml
      - version.yaml
      - app_secret.yaml
      - bkapigateway_builtin_keypair.yaml
---
releases:
  - name: probe6
    chart: /tmp/probe6
    values:
      - bkgse-ce-values.yaml.gotmpl
EOF

cd "$E" || exit 1
echo "===== 真渲染 GSE（前置齐备）====="
timeout 180 "$HF" -f zz_p6.yaml.gotmpl template > "$OUT/p6.log" 2>&1
rc=$?
echo "退出码: $rc"; echo "字节: $(wc -c < "$OUT/p6.log")"

if [ $rc -ne 0 ]; then
  echo "✗ 失败:"; grep -iE 'error|failed|no such file|no entry' "$OUT/p6.log" | head -6
  rm -f "$PROBE"; exit 1
fi

echo ""
echo "===== ★ 证书注入判定 ====="
grep -qE 'LS0t|BEGIN CERT' "$OUT/p6.log" && echo "★★★ 证书已真实注入（PEM 已 base64 进 values）" || echo "? 未见证书"

echo ""
echo "===== ca/cert/key 字段（前80字符）====="
grep -nE '^\s+(ca|cert|key):' "$OUT/p6.log" | head -6 | cut -c1-80

echo ""
echo "===== 规模 ====="
echo "总行数: $(wc -l < "$OUT/p6.log")"
echo "imageRegistry 出现次数: $(grep -c 'imageRegistry' "$OUT/p6.log")"

rm -f "$PROBE"; echo "已清理"
