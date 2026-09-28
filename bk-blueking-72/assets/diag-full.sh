#!/usr/bin/env bash
# 用途：取未截断的完整错误，定位缺失变量
set -uo pipefail
E=/root/bk72/install/blueking/environments/default
BIN=/root/bk72/tools/bin
HF=$BIN/helmfile
export PATH="$BIN:$PATH"

rm -rf /tmp/pf; mkdir -p /tmp/pf/templates
cat > /tmp/pf/Chart.yaml <<'EOF'
apiVersion: v2
name: pf
version: 0.1.0
EOF
: > /tmp/pf/values.yaml
printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: d\ndata:\n  all: |\n{{ toYaml .Values | indent 4 }}\n' > /tmp/pf/templates/dump.yaml

cd "$E" || exit 1
for f in bkgse-ee-values.yaml.gotmpl bkjob-values.yaml.gotmpl bkpaas3-values.yaml.gotmpl; do
  echo "########## $f ##########"
  P="$E/zz_ff.yaml.gotmpl"
  cat > "$P" <<EOF
environments:
  default:
    values:
      - values.yaml
      - version.yaml
      - app_secret.yaml
      - bkapigateway_builtin_keypair.yaml
---
releases:
  - name: pf
    chart: /tmp/pf
    values:
      - $f
EOF
  timeout 120 "$HF" -f zz_ff.yaml.gotmpl template > /tmp/ff.log 2>&1 || true
  # 提取 map has no entry for key "xxx" 的 xxx
  echo "缺失变量: $(grep -oE 'no entry for key "[^"]+"' /tmp/ff.log | sed 's/.*"\(.*\)"/\1/' | sort -u | tr '\n' ' ')"
  echo "行号: $(grep -oE 'stringTemplate:[0-9]+:[0-9]+' /tmp/ff.log | head -1)"
  echo "出错行内容:"
  ln=$(grep -oE 'stringTemplate:[0-9]+:' /tmp/ff.log | head -1 | grep -oE '[0-9]+')
  if [ -n "$ln" ]; then sed -n "${ln}p" "$f" | cut -c1-150; fi
  rm -f "$P"
  echo ""
done
