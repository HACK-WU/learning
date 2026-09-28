#!/usr/bin/env bash
set -uo pipefail
NS=blueking
echo "===== 1. redis-cluster Pod 是否转为 Ready ====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep 'bk-redis-cluster' | awk '{print "  "$1"  "$2"  "$3}'

echo ""
echo "===== 2. 全命名空间就绪统计 ====="
total=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | wc -l)
ready=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -cE '([0-9]+)/\1')
echo "  就绪: $ready / $total"

echo ""
echo "===== 3. StatefulSet 状态 ====="
kubectl get statefulset -n "$NS" --no-headers 2>/dev/null | awk '{printf "  %-46s %s\n", $1, $2}'

echo ""
echo "===== 4. 探针配置现状（决定是否需要方案C）====="
kubectl get statefulset bk-redis-cluster -n "$NS" -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
c=d['spec']['template']['spec']['containers'][0]
print('  livenessProbe :', json.dumps(c.get('livenessProbe')))
print('  readinessProbe:', json.dumps(c.get('readinessProbe')))
"
