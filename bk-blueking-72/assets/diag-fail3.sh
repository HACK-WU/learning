#!/usr/bin/env bash
# 用途：查 3 个渲染失败模板的真实原因（先核验，不臆断）
set -uo pipefail
E=/root/bk72/install/blueking/environments/default
BIN=/root/bk72/tools/bin
HF=$BIN/helmfile
OUT=/root/bk72/render_test
export PATH="$BIN:$PATH"

rm -rf /tmp/probef; mkdir -p /tmp/probef/templates
cat > /tmp/probef/Chart.yaml <<'EOF'
apiVersion: v2
name: probef
version: 0.1.0
EOF
: > /tmp/probef/values.yaml
cat > /tmp/probef/templates/dump.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: d
data:
  all: |
{{ toYaml .Values | indent 4 }}
EOF

cd "$E" || exit 1
for f in bkgse-ee-values.yaml.gotmpl bkjob-values.yaml.gotmpl bkpaas3-values.yaml.gotmpl; do
  echo "########## $f ##########"
  PROBE="$E/zz_f.yaml.gotmpl"
  cat > "$PROBE" <<EOF
environments:
  default:
    values:
      - values.yaml
      - version.yaml
      - app_secret.yaml
      - bkapigateway_builtin_keypair.yaml
---
releases:
  - name: probef
    chart: /tmp/probef
    values:
      - $f
EOF
  timeout 120 "$HF" -f zz_f.yaml.gotmpl template > "$OUT/f.log" 2>&1
  echo "--- 完整错误 ---"
  grep -iE 'error|no entry|no such file|because of' "$OUT/f.log" | head -3 | cut -c1-200
  echo "--- 该模板中引用的可疑变量 ---"
  grep -oE '\.Values\.[a-zA-Z_0-9]+' "$f" 2>/dev/null | sort -u | head -10
  rm -f "$PROBE"
  echo ""
done
