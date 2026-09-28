#!/usr/bin/env bash
# 诊断：CLUSTER MEET 报 Invalid node address 的根因
# 假设：节点 announce 地址与实际解析地址不一致
set -uo pipefail
NS=blueking
PW=8fsTmpFfVHFJ

echo "===== 1. 各节点实际监听地址 vs 通告地址 ====="
for p in bk-redis-cluster-0 bk-redis-cluster-1 bk-redis-cluster-2; do
  echo "--- $p ---"
  echo "  本机 IP: $(kubectl get pod $p -n $NS -o jsonpath='{.status.podIP}')"
  echo "  cluster-announce-ip: $(kubectl exec $p -n $NS -- redis-cli -a $PW config get cluster-announce-ip 2>/dev/null | tail -1)"
  echo "  cluster-announce-port: $(kubectl exec $p -n $NS -- redis-cli -a $PW config get cluster-announce-port 2>/dev/null | tail -1)"
  echo "  cluster-announce-bus-port: $(kubectl exec $p -n $NS -- redis-cli -a $PW config get cluster-announce-bus-port 2>/dev/null | tail -1)"
done

echo ""
echo "===== 2. headless service 域名解析（各 Pod 内视角）====="
for p in bk-redis-cluster-0 bk-redis-cluster-1 bk-redis-cluster-2; do
  echo "--- $p 解析 headless ---"
  kubectl exec $p -n $NS -- getent hosts bk-redis-cluster-headless 2>&1 | head -4
done

echo ""
echo "===== 3. 关键：Pod 0 能否解析 Pod 1/2 的 FQDN ====="
kubectl exec bk-redis-cluster-0 -n $NS -- getent hosts bk-redis-cluster-1.bk-redis-cluster-headless 2>&1 || echo "  ❌ 无法解析 -1"
kubectl exec bk-redis-cluster-0 -n $NS -- getent hosts bk-redis-cluster-2.bk-redis-cluster-headless 2>&1 || echo "  ❌ 无法解析 -2"

echo ""
echo "===== 4. 当前集群状态（部分组建的残留）====="
kubectl exec bk-redis-cluster-0 -n $NS -- redis-cli -a $PW cluster info 2>/dev/null | grep -E 'state|known_nodes|size|slots_assigned'
echo "--- 各节点 myself 视图 ---"
for p in bk-redis-cluster-0 bk-redis-cluster-1 bk-redis-cluster-2; do
  echo "  $p: $(kubectl exec $p -n $NS -- redis-cli -a $PW cluster nodes 2>/dev/null | head -2)"
done

echo ""
echo "===== 5. 集群总线端口 16379 是否可达（组建关键）====="
kubectl exec bk-redis-cluster-0 -n $NS -- sh -c 'timeout 3 bash -c "</dev/tcp/bk-redis-cluster-1.bk-redis-cluster-headless/16379" 2>&1 && echo "  ✅ 16379 可达 -1" || echo "  ❌ 16379 不通 -1"'
kubectl exec bk-redis-cluster-0 -n $NS -- sh -c 'timeout 3 bash -c "</dev/tcp/bk-redis-cluster-2.bk-redis-cluster-headless/16379" 2>&1 && echo "  ✅ 16379 可达 -2" || echo "  ❌ 16379 不通 -2"'
