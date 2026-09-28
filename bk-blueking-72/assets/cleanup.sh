#!/usr/bin/env bash
echo "===== 清理残留旧 Pod 并确认 ====="
echo ""
echo "--- 1. 确认有新旧两个 ReplicaSet ---"
kubectl get rs -n blueking --no-headers 2>/dev/null | grep -E 'bk-monitor-web-|bk-monitor-web-query-api-' | awk '{printf "  %-50s %-4s %-4s %s\n", $1, $2, $3, $4}'

echo ""
echo "--- 2. 删除 CrashLoopBackOff 的残留 Pod ---"
kubectl delete pod bk-monitor-web-6699f4d79c-tnw4t -n blueking --wait=false 2>&1 | sed 's/^/  /'
kubectl delete pod bk-monitor-web-query-api-699f99c694-x4pr5 -n blueking --wait=false 2>&1 | sed 's/^/  /'

echo ""
echo "--- 3. 等 60s 复查 ---"
sleep 60
echo "  总 Pod: $(kubectl get pods -n blueking --no-headers 2>/dev/null | wc -l)"
echo "  未就绪:"
kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3 != "Running" && $3 != "Completed" && $3 != "Succeeded" {printf "    %-45s %-12s %s\n", $1, $2, $3}' | head -10
echo "  (空 = 全部就绪)"

echo ""
echo "--- 4. 监控 web 与 query-api 最终状态 ---"
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-monitor-web|bk-monitor-grafana' | awk '{printf "  %-48s %-12s %s\n", $1, $2, $3}'
