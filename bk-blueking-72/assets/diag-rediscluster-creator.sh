#!/usr/bin/env bash
# 用途：查 redis-cluster-0（creator 节点）为什么没把其他节点拉进集群
set -uo pipefail
NS=blueking

echo "===== 1. creator 节点重启次数与时间线 ====="
kubectl get pod bk-redis-cluster-0 -n "$NS" -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for cs in d['status'].get('containerStatuses',[]):
    print('  restarts:', cs['restartCount'])
    print('  state:', json.dumps(cs.get('state',{}))[:200])
    print('  lastState:', json.dumps(cs.get('lastState',{}))[:300])
"

echo ""
echo "===== 2. 完整日志（找 cluster meet / create 关键字）====="
kubectl logs bk-redis-cluster-0 -n "$NS" 2>/dev/null | grep -iE 'cluster|meet|create|error|fail|warn' | head -25

echo ""
echo "===== 3. 上一次崩溃前的日志（关键！组建动作可能发生在崩溃前）====="
kubectl logs bk-redis-cluster-0 -n "$NS" --previous 2>/dev/null | tail -40

echo ""
echo "===== 4. creator 的 liveness/readiness 探针 ====="
kubectl get pod bk-redis-cluster-0 -n "$NS" -o jsonpath='{.spec.containers[0].livenessProbe}{\"\n\"}{.spec.containers[0].readinessProbe}{\"\n\"}' 2>/dev/null

echo ""
echo "===== 5. 三个节点的 cluster nodes 视图 ====="
for p in bk-redis-cluster-0 bk-redis-cluster-1 bk-redis-cluster-2; do
  echo "--- $p ---"
  kubectl exec "$p" -n "$NS" -- redis-cli -h 127.0.0.1 cluster nodes 2>&1 | head -5
done
