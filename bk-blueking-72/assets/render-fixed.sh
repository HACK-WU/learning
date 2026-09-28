#!/usr/bin/env bash
# 用途：修正探针——先加载全局 values.yaml，再渲染 GSE 模板
set -uo pipefail
E=/root/bk72/install/blueking/environments/default
HF=/root/bk72/tools/bin/helmfile
OUT=/root/bk72/render_test

rm -rf /tmp/probe3; mkdir -p /tmp/probe3/templates
cat > /tmp/probe3/Chart.yaml <<'EOF'
apiVersion: v2
name: probe3
version: 0.1.0
EOF
: > /tmp/probe3/values.yaml
cat > /tmp/probe3/templates/dump.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: values-dump
data:
  all: |
{{ toYaml .Values | indent 4 }}
EOF

PROBE="$E/zz_tpl3_probe.yaml.gotmpl"
cat > "$PROBE" <<'EOF'
bases:
  - ../../env.yaml
  - ../../defaults.yaml
---
releases:
  - name: probe3
    chart: /tmp/probe3
    values:
      - values.yaml
      - bkgse-ce-values.yaml.gotmpl
EOF

cd "$E" || exit 1
echo "===== 执行渲染（已加载全局 values.yaml）====="
timeout 180 "$HF" -f zz_tpl3_probe.yaml.gotmpl template > "$OUT/tpl3.log" 2>&1
rc=$?
echo "退出码: $rc"
echo "输出字节: $(wc -c < "$OUT/tpl3.log")"

if [ $rc -ne 0 ]; then
  echo "✗ 失败："
  grep -iE 'error|failed|no such file|not defined|no entry' "$OUT/tpl3.log" | head -8
  rm -f "$PROBE"; exit 1
fi

echo ""
echo "===== 判定：证书是否真注入 ====="
if grep -qE 'LS0t|BEGIN CERT' "$OUT/tpl3.log"; then
  echo "★★★ 证书已真实渲染注入（base64 内含 PEM 头）"
else
  echo "? 未见证书，查看输出"
fi

echo ""
echo "===== 提取 ca/cert/key 字段（截取前100字符）====="
grep -nE '^\s+(ca|cert|key):' "$OUT/tpl3.log" | head -6 | cut -c1-100

echo ""
echo "===== 统计渲染出的配置规模 ====="
echo "总行数: $(wc -l < "$OUT/tpl3.log")"
grep -cE 'imageRegistry' "$OUT/tpl3.log" | xargs echo "含 imageRegistry 的行数:"

rm -f "$PROBE"; echo "已清理探针"
