#!/usr/bin/env bash
set -uo pipefail
NS=blueking
echo "[1] PVC 绑定情况（验证复用集群 StorageClass 的决策是否长期成立）"
kubectl get pvc -n $NS --no-headers 2>/dev/null | awk '{print "    "$1" "$2" "$3}' | head -20
echo "    bound=$(kubectl get pvc -n $NS --no-headers 2>/dev/null | grep -c Bound)/$(kubectl get pvc -n $NS --no-headers 2>/dev/null | wc -l)"

echo "[2] StorageClass 用的是什么"
kubectl get pvc -n $NS -o jsonpath='{range .items[*]}{.spec.storageClassName}{"\n"}{end}' 2>/dev/null | sort -u | sed 's/^/    /'

echo "[3] 发布来源统计（helm install 还是补跑 Job）"
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '{print $1}' | sed 's/-[a-z0-9]*$//' | sort -u | wc -l | sed 's/^/    组件族数: /'

echo "[4] 节点资源（验证单机可行性结论）"
kubectl top node --no-headers 2>/dev/null | sed 's/^/    /'

echo "[5] 镜像拉取重试的痕迹：restarts 排行"
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '{if($4+0>0) print "    "$4" 次  "$1}' | sort -rn | head -8

echo "[6] 当前全部 Job 终态"
kubectl get jobs -n $NS --no-headers 2>/dev/null | awk '{print "    "$1" "$2" "$3}' | sort | uniq -c | sort -rn | head -10
