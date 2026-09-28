#!/usr/bin/env bash
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH
NS=blueking

echo "===== 1. second 批三个 release 状态 ====="
helm list -n $NS --no-headers 2>/dev/null | grep -E 'bk-iam|bk-ssm|bk-console' | awk '{printf "  %-12s %-10s rev%s\n", $1, $8, $2}'

echo ""
echo "===== 2. second 批 Pod 明细 ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'bkiam|bkssm|bk-console|console' | awk '{printf "  %-50s %-12s %s\n", $1, $3, $2}'

echo ""
echo "===== 3. 全命名空间 Pod 统计 ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn | sed 's/^/  /'
echo "  总计: $(kubectl get pods -n $NS --no-headers 2>/dev/null | wc -l)"

echo ""
echo "===== 4. 非 Running/Completed 的 Pod（关键）====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -vE 'Running|Completed' | awk '{printf "  %-50s %s\n", $1, $3}' || true

echo ""
echo "===== 5. second 批 Ingress ====="
kubectl get ingress -n $NS --no-headers 2>/dev/null | grep -E 'bkiam|bkssm|console' | awk '{printf "  %-16s %-34s %s\n", $1, $2, $4}'

echo ""
echo "===== 6. 全批次 release 总览 ====="
helm list -n $NS --no-headers 2>/dev/null | awk '{printf "  %-16s %-10s\n", $1, $8}'
