#!/usr/bin/env bash
# 用途：诊断 bk-redis-cluster 0/3 —— 是探针杀？还是集群没组建起来？
set -uo pipefail
NS=blueking

echo "===== 1. 三个 Pod 的详细状态与重启次数 ====="
for p in bk-redis-cluster-0 bk-redis-cluster-1 bk-redis-cluster-2; do
  kubectl get pod "$p" -n "$NS" -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for cs in d['status'].get('containerStatuses',[]):
    print(f\"  pod={d['metadata']['name']}  ready={cs['ready']}  restarts={cs['restartCount']}  state={list(cs.get('state',{}).keys())}\")
"
done

echo ""
echo "===== 2. 事件原文（找 Killing / Unhealthy 原因）====="
for p in bk-redis-cluster-0 bk-redis-cluster-1 bk-redis-cluster-2; do
  echo "--- $p ---"
  kubectl get events -n "$NS" --field-selector involvedObject.name="$p" --sort-by=.lastTimestamp 2>/dev/null | tail -5
done

echo ""
echo "===== 3. 容器日志（看集群组建进度）====="
for p in bk-redis-cluster-0 bk-redis-cluster-1 bk-redis-cluster-2; do
  echo "--- $p ---"
  kubectl logs "$p" -n "$NS" --tail=25 2>/dev/null | tail -25
done

echo ""
echo "===== 4. 节点是否为 Ready（探针是否可达）====="
kubectl exec bk-redis-cluster-0 -n "$NS" -- redis-cli -h 127.0.0.1 ping 2>&1 | head -3
echo "--- cluster info ---"
kubectl exec bk-redis-cluster-0 -n "$NS" -- redis-cli -h 127.0.0.1 cluster info 2>&1 | head -8
