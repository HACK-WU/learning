#!/usr/bin/env bash
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH
NS=blueking

echo "===== 1. third 批 release 状态 ====="
helm list -n $NS --no-headers 2>/dev/null | grep -E 'bk-user|bk-iam-saas|bk-iam-search|bk-gse|bk-cmdb|bk-paas|bk-applog|bk-ingress' | awk '{printf "  %-22s %s\n", $1, $8}'
echo "  --- bkpaas-app-operator 在独立 ns ---"
helm list -n bkpaas-app-operator-system --no-headers 2>/dev/null | awk '{printf "  %-22s %s\n", $1, $8}'

echo ""
echo "===== 2. Pod 总览（按状态）====="
kubectl get pods -A --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn | sed 's/^/  /'
echo "  blueking ns 总计: $(kubectl get pods -n $NS --no-headers 2>/dev/null | wc -l)"

echo ""
echo "===== 3. 异常 Pod（非 Running/Completed）====="
kubectl get pods -A --no-headers 2>/dev/null | grep -vE 'Running|Completed' | awk '{printf "  %-16s %-52s %s\n", $1, $2, $4}' | sed 's/^/  /'

echo ""
echo "===== 4. third 批关键 Pod 抽样 ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'cmdb|paas3|gse|bk-user|bk-login|applog' | awk '{printf "  %-50s %-12s %s\n", $1, $3, $2}' | head -25

echo ""
echo "===== 5. 所有 release 总览 ====="
helm list -A --no-headers 2>/dev/null | awk '{printf "  %-24s %-10s %s\n", $1, $8, $2}' | sort
