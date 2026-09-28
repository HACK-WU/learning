#!/usr/bin/env bash
set -uo pipefail
{
echo "===== migrate Job 当前状态 ====="
kubectl get job -n blueking --no-headers 2>/dev/null | grep -iE 'monitor.*migrate' | sed 's/^/  /' || echo "  (无 migrate Job)"

echo ""
echo "===== migrate Pod 与日志（关键：403 是否消失）====="
MPOD=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'monitor.*migrate' | awk '{print $1}' | head -1)
echo "  POD=$MPOD"
if [ -n "$MPOD" ]; then
  kubectl get pod "$MPOD" -n blueking --no-headers 2>/dev/null | sed 's/^/  /'
  echo "  --- 日志尾部 40 行 ---"
  kubectl logs "$MPOD" -n blueking --tail=40 2>&1 | sed 's/^/  /'
  echo "  --- 是否仍报 403 ---"
  kubectl logs "$MPOD" -n blueking 2>/dev/null | grep -icE '403' | sed 's/^/  403出现次数: /'
fi

echo ""
echo "===== bk-monitor release 状态 ====="
helm list -A 2>/dev/null | grep -E 'bk-monitor' | sed 's/^/  /'

echo ""
echo "===== 监控 Pod 总览 ====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -i 'bk-monitor' | awk '{print $2, $3}' | sort | uniq -c | sed 's/^/  /'

echo ""
echo "===== web Pod 是否解卡 ====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-monitor-web' | sed 's/^/  /'
} > /root/migrate-result.txt 2>&1
cat /root/migrate-result.txt
