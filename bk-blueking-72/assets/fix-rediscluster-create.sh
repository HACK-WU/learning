#!/usr/bin/env bash
# 步骤 A：手动组建 redis-cluster（三节点，0 副本）
# 前提：三个 Pod 必须已稳定（重启次数不再增长）
set -uo pipefail
NS=blueking
PW=8fsTmpFfVHFJ

echo "===== 0. 组建前稳定性检查 ====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep 'bk-redis-cluster' | awk '{print "  "$1"  "$2"  "$3}'
echo "--- 各节点重启次数（应停止增长）---"
for p in bk-redis-cluster-0 bk-redis-cluster-1 bk-redis-cluster-2; do
  r=$(kubectl get pod "$p" -n "$NS" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
  echo "  $p restarts=$r"
done

echo ""
echo "===== 1. 组建前 cluster info（应为 fail / known_nodes:1）====="
kubectl exec bk-redis-cluster-0 -n "$NS" -- redis-cli -a "$PW" cluster info 2>/dev/null | grep -E 'cluster_state|cluster_known_nodes|cluster_slots_assigned'

echo ""
echo "===== 2. 执行 cluster create ====="
kubectl exec bk-redis-cluster-0 -n "$NS" -- \
  redis-cli -a "$PW" --cluster create \
  bk-redis-cluster-0.bk-redis-cluster-headless:6379 \
  bk-redis-cluster-1.bk-redis-cluster-headless:6379 \
  bk-redis-cluster-2.bk-redis-cluster-headless:6379 \
  --cluster-replicas 0 --cluster-yes 2>&1 | tail -30

echo ""
echo "===== 3. 组建后验证 ====="
sleep 5
kubectl exec bk-redis-cluster-0 -n "$NS" -- redis-cli -a "$PW" cluster info 2>/dev/null | grep -E 'cluster_state|cluster_known_nodes|cluster_size|cluster_slots_assigned'
echo "--- cluster nodes ---"
kubectl exec bk-redis-cluster-0 -n "$NS" -- redis-cli -a "$PW" cluster nodes 2>/dev/null
