#!/usr/bin/env bash
# 用途：核验 redis-cluster 崩溃是否真为 OOMKilled（137 可能是 OOM 也可能是探针 kill）
set -uo pipefail
NS=blueking
POD=bk-redis-cluster-2

echo "===== 1. 137 的两种可能：OOMKilled vs 主动 kill ====="
echo "--- 查 OOM 事件 ---"
kubectl get events -n "$NS" --field-selector involvedObject.name="$POD" 2>&1 | grep -i oom | head -5
echo "(空=无 OOM 事件)"

echo ""
echo "--- 查节点内核 OOM 日志 ---"
dmesg 2>/dev/null | grep -iE 'killed process|out of memory' | tail -8
echo "(需 root，空则无权限或无记录)"

echo ""
echo "===== 2. 容器内存 limits（关键：超限会被 cgroup OOM kill）====="
kubectl get pod "$POD" -n "$NS" -o jsonpath='{.spec.containers[0].resources}' 2>&1
echo ""

echo ""
echo "===== 3. 对比：redis-cluster-0/1 的资源设置 ====="
for p in bk-redis-cluster-0 bk-redis-cluster-1; do
  echo "--- $p ---"
  kubectl get pod "$p" -n "$NS" -o jsonpath='{.spec.containers[0].resources}' 2>&1
  echo ""
done

echo ""
echo "===== 4. livenessProbe 配置（超时会 kill，但通常是 143 而非 137）====="
kubectl get pod "$POD" -n "$NS" -o jsonpath='{.spec.containers[0].livenessProbe}' 2>&1
echo ""

echo ""
echo "===== 5. 节点可用内存（判断是否节点级 OOM）====="
free -m | head -2
