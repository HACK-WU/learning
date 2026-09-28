#!/usr/bin/env bash
set -uo pipefail
NS=blueking
echo "===== 1. paas3 全家桶 Pod 状态 ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E '^bkpaas3' | awk '{printf "    %-52s %-10s %-6s %s\n", $1, $3, $4, $5}'
echo ""
echo "  统计: total=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -cE '^bkpaas3')  running=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E '^bkpaas3' | grep -c Running)  notready=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E '^bkpaas3' | grep -vcE 'Running|Completed')"

echo ""
echo "===== 2. paas3 相关 Job 终态 ====="
kubectl get jobs -n $NS --no-headers 2>/dev/null | grep -E '^bkpaas3' | awk '{printf "    %-56s %-10s %s\n", $1, $3, $2}' | sort

echo ""
echo "===== 3. paas3 服务与端口 ====="
kubectl get svc -n $NS --no-headers 2>/dev/null | grep -E 'bkpaas3' | awk '{printf "    %-46s %-12s %s\n", $1, $2, $5}'

echo ""
echo "===== 4. 关键 Deployment 就绪 ====="
kubectl get deploy -n $NS --no-headers 2>/dev/null | grep -E 'bkpaas3' | awk '{printf "    %-46s %s\n", $1, $2}'

echo ""
echo "===== 5. 最近是否有重启/异常事件 ====="
kubectl get events -n $NS --sort-by=.lastTimestamp --no-headers 2>/dev/null | grep -iE 'bkpaas3' | tail -6 | sed 's/^/    /'
