#!/usr/bin/env bash
set -uo pipefail
NS=blueking
echo "===== blueking 命名空间全部 ingress 域名（去重）====="
kubectl get ingress -n $NS -o jsonpath='{range .items[*]}{.spec.rules[*].host}{"\n"}{end}' 2>/dev/null \
  | tr ' ' '\n' | grep -v '^$' | sort -u | sed 's/^/    /'

echo ""
echo "===== 其他命名空间是否也有 ingress ====="
kubectl get ingress -A --no-headers 2>/dev/null | awk '{print $1}' | sort | uniq -c | sed 's/^/    /'
