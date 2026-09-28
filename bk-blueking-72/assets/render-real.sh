#!/usr/bin/env bash
# 用途：用 helmfile template 强制渲染 values（build 只输出 state，不渲染 values）
set -uo pipefail
B=/root/bk72/install/blueking
E=$B/environments/default
HF=/root/bk72/tools/bin/helmfile
OUT=/root/bk72/render_test
mkdir -p "$OUT"

echo "===== 准备探针 chart（带一个能显示 values 的模板）====="
rm -rf /tmp/probe2; mkdir -p /tmp/probe2/templates
cat > /tmp/probe2/Chart.yaml <<'EOF'
apiVersion: v2
name: probe2
version: 0.1.0
EOF
cat > /tmp/probe2/values.yaml <<'EOF'
EOF
# 关键：把整个 values 打印出来，强制 helm 渲染
cat > /tmp/probe2/templates/dump.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: values-dump
data:
  all: |
{{ toYaml .Values | indent 4 }}
EOF

PROBE="$E/zz_tpl_probe.yaml.gotmpl"
cat > "$PROBE" <<'EOF'
bases:
  - ../../env.yaml
  - ../../defaults.yaml
---
releases:
  - name: gse-probe
    chart: /tmp/probe2
    values:
      - bkgse-ce-values.yaml.gotmpl
EOF

cd "$E" || exit 1
echo ""
echo "===== 执行 helmfile template（强制渲染）====="
timeout 180 "$HF" -f zz_tpl_probe.yaml.gotmpl template > "$OUT/tpl.log" 2>&1
rc=$?
echo "退出码: $rc"
echo "输出字节: $(wc -c < "$OUT/tpl.log")"

echo ""
echo "===== 判定：是否真渲染出证书 ====="
if [ $rc -eq 0 ]; then
  if grep -qE 'LS0t|gseca|BEGIN CERT' "$OUT/tpl.log"; then
    echo "★★ 证书已真实渲染（readFile 生效）"
  else
    echo "? 渲染成功但未见证书，看输出头部"
    head -30 "$OUT/tpl.log"
  fi
else
  echo "✗ 渲染失败："
  grep -iE 'error|failed|no such file|not defined' "$OUT/tpl.log" | head -10
fi

echo ""
echo "===== 关键片段：ca/cert 字段 ====="
grep -nE '^\s+(ca|cert|key):' "$OUT/tpl.log" | head -8 | cut -c1-120

rm -f "$PROBE"; echo "已清理"
