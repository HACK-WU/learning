#!/usr/bin/env bash
# 步骤 A2：改用 Pod IP 组建（Redis 6.2 的 Invalid node address 绕行）
# 现状：三节点已各自持有 slots，只是互不相认 → 用 CLUSTER MEET + 复用已有 slots
set -uo pipefail
NS=blueking
PW=8fsTmpFfVHFJ

IP0=$(kubectl get pod bk-redis-cluster-0 -n $NS -o jsonpath='{.status.podIP}')
IP1=$(kubectl get pod bk-redis-cluster-1 -n $NS -o jsonpath='{.status.podIP}')
IP2=$(kubectl get pod bk-redis-cluster-2 -n $NS -o jsonpath='{.status.podIP}')
echo "节点 IP: 0=$IP0  1=$IP1  2=$IP2"

echo ""
echo "===== 1. 用 IP 执行 CLUSTER MEET（从 -0 发起）====="
echo "--- meet $IP1 ---"
kubectl exec bk-redis-cluster-0 -n $NS -- redis-cli -a $PW cluster meet $IP1 6379 2>/dev/null
echo "--- meet $IP2 ---"
kubectl exec bk-redis-cluster-0 -n $NS -- redis-cli -a $PW cluster meet $IP2 6379 2>/dev/null

echo ""
echo "===== 2. 等待握手（10秒）====="
sleep 10

echo ""
echo "===== 3. 验证集群视图 ====="
kubectl exec bk-redis-cluster-0 -n $NS -- redis-cli -a $PW cluster info 2>/dev/null | grep -E 'cluster_state|cluster_known_nodes|cluster_size|cluster_slots_assigned|cluster_slots_ok'
echo "--- cluster nodes ---"
kubectl exec bk-redis-cluster-0 -n $NS -- redis-cli -a $PW cluster nodes 2>/dev/null

echo ""
echo "===== 4. 若仍 fail：检查 slots 冲突 ====="
kubectl exec bk-redis-cluster-0 -n $NS -- redis-cli -a $PW cluster info 2>/dev/null | grep 'cluster_state'
