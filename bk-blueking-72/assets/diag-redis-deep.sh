#!/usr/bin/env bash
# 用途：深入诊断 redis-cluster 崩溃——看完整日志与退出码
set -uo pipefail
NS=blueking
POD=bk-redis-cluster-2

echo "===== 1. 容器状态 + 退出码 ====="
kubectl get pod "$POD" -n "$NS" -o jsonpath='{range .status.containerStatuses[*]}name={.name}{"\n"}  ready={.ready}{"\n"}  restartCount={.restartCount}{"\n"}  lastState={.lastState}{"\n"}  exitCode={.lastState.terminated.exitCode}{"\n"}  reason={.lastState.terminated.reason}{"\n"}{end}' 2>&1

echo ""
echo "===== 2. 完整日志（不限 tail）====="
kubectl logs "$POD" -n "$NS" 2>&1 | tail -30

echo ""
echo "===== 3. redis-cluster-0/1 是否也崩 ====="
kubectl get pods -n "$NS" -l app=redis-cluster 2>&1
for p in bk-redis-cluster-0 bk-redis-cluster-1; do
  echo "--- $p ---"
  kubectl logs "$p" -n "$NS" --tail=15 2>&1 | tail -15
done

echo ""
echo "===== 4. PVC 是否 Bound ====="
kubectl get pvc -n "$NS" | grep redis-cluster

echo ""
echo "===== 5. 内核参数 vm.overcommit_memory（redis 常见杀手）====="
sysctl vm.overcommit_memory 2>&1
grep -n 'vm.overcommit' /etc/sysctl.conf 2>/dev/null

echo ""
echo "===== 6. 节点内存压力 ====="
free -g | head -3
