#!/usr/bin/env bash
# 核验：集群配置是否持久化（决定重启后是否会自动恢复 → 方案C是否必要）
set -uo pipefail
NS=blueking

echo "===== 1. 集群配置 nodes.conf 是否落盘（PVC 持久化）====="
kubectl exec bk-redis-cluster-0 -n $NS -- sh -c 'ls -la /bitnami/redis/data/ 2>/dev/null | head -12; echo "--- nodes.conf 内容 ---"; head -8 /bitnami/redis/data/nodes.conf 2>/dev/null' 2>&1

echo ""
echo "===== 2. readiness latch 文件（关键：存在则永久跳过集群检查）====="
kubectl exec bk-redis-cluster-0 -n $NS -- sh -c 'ls -la /tmp/.redis_cluster_check 2>&1' 2>&1

echo ""
echo "===== 3. 三个节点 restarts 现状（是否还在被杀）====="
for p in 0 1 2; do
  echo "  bk-redis-cluster-$p: restarts=$(kubectl get pod bk-redis-cluster-$p -n $NS -o jsonpath='{.status.containerStatuses[0].restartCount}')"
done

echo ""
echo "===== 4. 下一步：helmfile / 批次结构 ====="
ls /root/bk72/install/blueking/ 2>&1 | head -25

echo ""
echo "===== 5. 查找 seq 批次定义 ====="
find /root/bk72/install/blueking -maxdepth 2 -name 'helmfile*' 2>/dev/null | head -10
grep -rn 'seq' /root/bk72/install/blueking/helmfile.yaml 2>/dev/null | head -15
