#!/usr/bin/env bash
# 用途：用真实 chart + 真实 values 渲染，验证是否具备真部署条件
set -uo pipefail
B=/root/bk72/install/blueking
E=$B/environments/default
BIN=/root/bk72/tools/bin
HF=$BIN/helmfile
export PATH="$BIN:$PATH"

echo "===== 1. 选取基础存储类 chart（不依赖 SaaS）====="
ls -1 "$B"/charts/*.tgz | head -20

echo ""
echo "===== 2. 用真实 chart 渲染（mysql 为例）====="
CH="$B/charts/mysql-10.3.0.tgz"
VF="$E/mysql-values.yaml.gotmpl"
if [ -f "$CH" ] && [ -f "$VF" ]; then
  P="$E/zz_real.yaml.gotmpl"
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
  - name: mysql-real
    chart: $CH
    namespace: blueking
    values:
      - mysql-values.yaml.gotmpl
EOF
  cd "$E" || exit 1
  timeout 180 "$HF" -f zz_real.yaml.gotmpl template > /tmp/real.log 2>&1
  rc=$?
  echo "退出码: $rc"
  if [ $rc -eq 0 ]; then
    echo "★★★ 真实 chart 渲染成功"
    echo "产出 K8s 对象数: $(grep -c '^kind:' /tmp/real.log)"
    grep '^kind:' /tmp/real.log | sort | uniq -c | head -8
  else
    echo "✗ 失败:"; grep -iE 'error|no entry|not found' /tmp/real.log | head -5 | cut -c1-160
  fi
  rm -f "$P"
else
  echo "chart 或 values 缺失"
fi
