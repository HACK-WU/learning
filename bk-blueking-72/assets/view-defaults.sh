#!/usr/bin/env bash
# 用途：看清 base-storage 9 个组件哪些默认启用 + 资源设置
set -uo pipefail
B=/root/bk72/install/blueking
E=$B/environments/default

echo "===== 1. defaults.yaml（启用开关）====="
cat "$B/defaults.yaml"

echo ""
echo "===== 2. 各存储组件的资源 requests/limits ====="
for c in mysql mysql8 rabbitmq redis redis-cluster mongodb elasticsearch zookeeper etcd; do
  f="$E/$c-custom-values.yaml.gotmpl"
  if [ -f "$f" ]; then
    echo "--- $c-custom-values ---"
    grep -nA2 -E 'requests:|limits:|memory:|cpu:' "$f" 2>/dev/null | head -14
  fi
done
