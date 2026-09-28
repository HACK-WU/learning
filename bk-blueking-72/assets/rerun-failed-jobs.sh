#!/usr/bin/env bash
# A+B：重跑失败 Job 抓真实报错
# 原则：先备份现场 → 再删除重建 → 快速失败保留 Pod 供看日志
set -uo pipefail
NS=blueking
BAK=/root/bk72/install/bk-job-backup-$(date +%Y%m%d-%H%M%S)
mkdir -p $BAK

echo "===== 0. 备份所有相关 Job 定义 ====="
for j in $(kubectl get jobs -n $NS --no-headers 2>/dev/null | awk '{print $1}'); do
  kubectl get job $j -n $NS -o yaml > $BAK/$j.yaml 2>/dev/null
done
echo "  已备份 $(ls $BAK | wc -l) 个 Job 到 $BAK"

echo ""
echo "===== 1. 当前失败/未完成 Job 状态 ====="
kubectl get jobs -n $NS --no-headers 2>/dev/null | awk '$2!="1/1" {printf "  %-46s %-10s 失败%s\n", $1, $2, $3}' | head -20

echo ""
echo "===== 2. 定位 apigw sync 类 Job ====="
kubectl get jobs -n $NS --no-headers 2>/dev/null | grep -iE 'apigw|sync' | awk '{printf "  %-46s %-10s 失败%s\n", $1, $2, $3}'

echo ""
echo "===== 3. 重建 paas3 migrate-db（BackoffLimitExceeded 必须删 Job）====="
J=bkpaas3-apiserver-migrate-db-1
if kubectl get job $J -n $NS >/dev/null 2>&1; then
  kubectl get job $J -n $NS -o json > /tmp/j-src.json 2>/dev/null
  python3 - <<'PY'
import json
j = json.load(open('/tmp/j-src.json'))
m = j['metadata']
for k in ['uid','resourceVersion','creationTimestamp','generation','managedFields','ownerReferences','selfLink','namespace']:
    m.pop(k, None)
j.pop('status', None)
# 快速失败：backoffLimit=1，避免像上次那样重试到 Pod 被回收
j['spec']['backoffLimit'] = 1
j['spec'].pop('ttlSecondsAfterFinished', None)
t = j['spec']['template']['metadata']
for k in ['creationTimestamp','managedFields','ownerReferences','labels']:
    t.pop(k, None)
json.dump(j, open('/tmp/j-new.json','w'))
print("  job 定义已清洗 (backoffLimit=1)")
PY
  kubectl delete job $J -n $NS --wait=false 2>&1 | sed 's/^/  /'
  sleep 3
  kubectl apply -f /tmp/j-new.json -n $NS 2>&1 | sed 's/^/  /'
else
  echo "  Job $J 不存在，跳过"
fi

echo ""
echo "===== 4. 触发 apigw sync 重跑（删 Pod 让 Job 重建）====="
for p in $(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -iE 'apigw|apigateway-sync' | grep -vE 'Running|Completed' | awk '{print $1}'); do
  echo "  删除异常 Pod: $p"
  kubectl delete pod $p -n $NS --wait=false 2>&1 | sed 's/^/    /'
done

echo ""
echo "===== 5. cmdb migrate-dataid 重跑 ====="
for p in $(kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'migrate-dataid' | grep -vE 'Running|Completed' | awk '{print $1}'); do
  echo "  删除异常 Pod: $p"
  kubectl delete pod $p -n $NS --wait=false 2>&1 | sed 's/^/    /'
done

echo ""
echo "  备份目录: $BAK"
