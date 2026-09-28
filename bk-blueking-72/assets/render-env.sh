#!/usr/bin/env bash
# 用途：用 helmfile 官方 environments 机制注入全局 values，再渲染 GSE 模板
set -uo pipefail
E=/root/bk72/install/blueking/environments/default
HF=/root/bk72/tools/bin/helmfile
OUT=/root/bk72/render_test

rm -rf /tmp/probe4; mkdir -p /tmp/probe4/templates
cat > /tmp/probe4/Chart.yaml <<'EOF'
apiVersion: v2
name: probe4
version: 0.1.0
EOF
: > /tmp/probe4/values.yaml
cat > /tmp/probe4/templates/dump.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: values-dump
data:
  all: |
{{ toYaml .Values | indent 4 }}
EOF

# 关键：用 environments.default.values 注入，而不是 bases
PROBE="$E/zz_tpl4_probe.yaml.gotmpl"
cat > "$PROBE" <<'EOF'
environments:
  default:
    values:
      - values.yaml
      - version.yaml
---
releases:
  - name: probe4
    chart: /tmp/probe4
    values:
      - bkgse-ce-values.yaml.gotmpl
EOF

cd "$E" || exit 1
echo "===== 用 environments 机制渲染 ====="
timeout 180 "$HF" -f zz_tpl4_probe.yaml.gotmpl template > "$OUT/tpl4.log" 2>&1
rc=$?
echo "退出码: $rc"; echo "输出字节: $(wc -c < "$OUT/tpl4.log")"

if [ $rc -ne 0 ]; then
  echo "✗ 失败："; grep -iE 'error|failed|no such file|no entry' "$OUT/tpl4.log" | head -6
  rm -f "$PROBE"; exit 1
fi

echo ""
echo "===== 判定证书注入 ====="
grep -qE 'LS0t|BEGIN CERT' "$OUT/tpl4.log" && echo "★★★ 证书已真实注入" || echo "? 未见证书"

echo ""
echo "===== ca/cert/key 字段 ====="
grep -nE '^\s+(ca|cert|key):' "$OUT/tpl4.log" | head -6 | cut -c1-100

echo ""
echo "===== 规模 ====="
echo "总行数: $(wc -l < "$OUT/tpl4.log")"

rm -f "$PROBE"; echo "已清理"
