#!/usr/bin/env bash
set -uo pipefail
OUT=/root/final-verify.txt
MPOD=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep 'bk-monitor-migrate' | awk '{print $1}' | head -1)
{
echo "===== 方案 A 完整验证 ====="
echo ""
echo "--- 1. migrate Job 与 Pod 状态 ---"
kubectl get job -n blueking --no-headers 2>/dev/null | grep -i 'monitor.*migrate' | sed 's/^/  /'
echo "  pod = $MPOD  状态=$(kubectl get pod $MPOD -n blueking -o jsonpath='{.status.phase}' 2>/dev/null)"
echo "  403 次数 = $(kubectl logs $MPOD -n blueking --all-containers 2>/dev/null | grep -icE '403')"

echo ""
echo "--- 2. migrate 日志尾部 ---"
kubectl logs "$MPOD" -n blueking --all-containers --tail=25 2>/dev/null | cut -c1-200 | sed 's/^/  /'

echo ""
echo "--- 3. 监控 Pod 状态 ---"
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'bk-monitor' | awk '{print "  "$1"  "$2"  "$3}' | head -20

echo ""
echo "--- 4. 等 90s 再看 ---"
sleep 90
kubectl get job -n blueking --no-headers 2>/dev/null | grep -i 'monitor.*migrate' | sed 's/^/  /'
echo "  403 次数 = $(kubectl logs $MPOD -n blueking --all-containers 2>/dev/null | grep -icE '403')"
} 2>&1 | tee "$OUT"
