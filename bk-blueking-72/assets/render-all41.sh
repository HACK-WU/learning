#!/usr/bin/env bash
# 用途：全量渲染验证——逐个渲染 41 个 values 模板，统计成功率
set -uo pipefail
E=/root/bk72/install/blueking/environments/default
BIN=/root/bk72/tools/bin
HF=$BIN/helmfile
OUT=/root/bk72/render_test
export PATH="$BIN:$PATH"
mkdir -p "$OUT"

rm -rf /tmp/probeall; mkdir -p /tmp/probeall/templates
cat > /tmp/probeall/Chart.yaml <<'EOF'
apiVersion: v2
name: probeall
version: 0.1.0
EOF
: > /tmp/probeall/values.yaml
cat > /tmp/probeall/templates/dump.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: values-dump
data:
  all: |
{{ toYaml .Values | indent 4 }}
EOF

cd "$E" || exit 1
ok=0; fail=0
: > "$OUT/all_result.txt"
for f in *-values.yaml.gotmpl; do
  PROBE="$E/zz_all.yaml.gotmpl"
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
  - name: probeall
    chart: /tmp/probeall
    values:
      - $f
EOF
  if timeout 120 "$HF" -f zz_all.yaml.gotmpl template > "$OUT/last.log" 2>&1; then
    echo "OK   $f" >> "$OUT/all_result.txt"; ok=$((ok+1))
  else
    err=$(grep -iE 'error|no entry|no such file' "$OUT/last.log" | head -1 | cut -c1-110)
    echo "FAIL $f | $err" >> "$OUT/all_result.txt"; fail=$((fail+1))
  fi
  rm -f "$PROBE"
done

echo "===== 全量渲染结果 ====="
echo "成功: $ok / $((ok+fail))"
echo "失败: $fail"
echo ""
echo "===== 失败明细 ====="
grep '^FAIL' "$OUT/all_result.txt" | head -20
echo ""
echo "===== 成功样例（前10）====="
grep '^OK' "$OUT/all_result.txt" | head -10
