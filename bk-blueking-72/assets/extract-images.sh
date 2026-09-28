#!/usr/bin/env bash
# 用途：渲染真实 chart，从产出 YAML 中提取「最终镜像名」（最可靠，不靠猜）
set -uo pipefail
B=/root/bk72/install/blueking
E=$B/environments/default
BIN=/root/bk72/tools/bin
HF=$BIN/helmfile
export PATH="$BIN:$PATH"

rm -rf /tmp/pimg; mkdir -p /tmp/pimg/templates
cat > /tmp/pimg/Chart.yaml <<'EOF'
apiVersion: v2
name: pimg
version: 0.1.0
EOF
: > /tmp/pimg/values.yaml
printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: d\ndata:\n  all: |\n{{ toYaml .Values | indent 4 }}\n' > /tmp/pimg/templates/dump.yaml

cd "$E" || exit 1
echo "===== 渲染真实基础存储 chart，提取镜像 ====="
for pair in "mysql-10.3.0.tgz:mysql-values.yaml.gotmpl" "redis-16.13.2.tgz:redis-values.yaml.gotmpl" "mongodb-10.30.6.tgz:mongodb-values.yaml.gotmpl"; do
  CH="${pair%%:*}"; VF="${pair##*:}"
  P="$E/zz_img.yaml.gotmpl"
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
  - name: img
    chart: $B/charts/$CH
    namespace: blueking
    values:
      - $VF
EOF
  echo "--- $CH ---"
  timeout 180 "$HF" -f zz_img.yaml.gotmpl template 2>/dev/null | grep -oE 'image:[[:space:]]*"?[^"[:space:]]+"?' | sed 's/image:[[:space:]]*//; s/"//g' | sort -u | head -5
  rm -f "$P"
done

echo ""
echo "===== 从 values.yaml 看 imageRegistry 与全局镜像规则 ====="
grep -nE 'imageRegistry|imagePull|registry' "$E/values.yaml" | head -8
