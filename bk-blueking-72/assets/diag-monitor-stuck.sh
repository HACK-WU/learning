#!/usr/bin/env bash
set -uo pipefail

echo "===== 1. migrate Job 日志（CrashLoopBackOff 根因）====="
kubectl logs -n blueking job/bk-monitor-migrate 2>/dev/null | tail -30 | sed 's/^/  /'
echo "  --- 若无输出，试 Pod ---"
P=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep 'bk-monitor-migrate' | awk '{print $1}' | head -1)
echo "  migrate pod: $P"
[ -n "$P" ] && kubectl logs -n blueking "$P" --all-containers 2>/dev/null | tail -30 | sed 's/^/  /'

echo ""
echo "===== 2. 一个 Init 卡住的 Pod 的 init 容器状态 ===="
P2=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep 'bk-monitor-api' | awk '{print $1}' | head -1)
echo "  pod: $P2"
[ -n "$P2" ] && kubectl describe pod -n blueking "$P2" 2>/dev/null | grep -A20 -E 'Init Containers:|Events:' | tail -40 | sed 's/^/  /'

echo ""
echo "===== 3. init 容器日志（通常在等 migrate）====="
[ -n "$P2" ] && kubectl logs -n blueking "$P2" -c $(kubectl get pod -n blueking "$P2" -o jsonpath='{.spec.initContainers[0].name}' 2>/dev/null) 2>/dev/null | tail -20 | sed 's/^/  /'

echo ""
echo "===== 4. 集群事件（找错误）====="
kubectl get events -n blueking --sort-by='.lastTimestamp' 2>/dev/null | grep -iE 'monitor' | tail -15 | sed 's/^/  /'
