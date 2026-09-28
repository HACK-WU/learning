#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. migrate-db Job 当前状态 ====="
kubectl get job bkpaas3-apiserver-migrate-db-1 -n $NS --no-headers 2>&1 | awk '{printf "  %-46s %-10s\n", $1, $2}'
kubectl get job bkpaas3-apiserver-migrate-db-1 -n $NS -o jsonpath='  succeeded={.status.succeeded} failed={.status.failed} active={.status.active}{"\n"}' 2>&1

echo ""
echo "===== 2. 最近的 Pod 事件（看谁在删 Pod）====="
kubectl get events -n $NS --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -15 | awk '{printf "  %-8s %-24s %-40s %s\n", $2, $3, $4, substr($0, index($0,$5), 60)}'

echo ""
echo "===== 3. 是否有 helm 操作在跑 ====="
ps aux 2>/dev/null | grep -iE 'helm|helmfile' | grep -v grep | head -5 | sed 's/^/  /'
kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -iE 'helm' | sed 's/^/  /'

echo ""
echo "===== 4. 是否 Job 有 ttlSecondsAfterFinished ====="
kubectl get job bkpaas3-apiserver-migrate-db-1 -n $NS -o jsonpath='  ttl={.spec.ttlSecondsAfterFinished}  backoff={.spec.backoffLimit}{"\n"}' 2>&1

echo ""
echo "===== 5. 关键：直接在诊断 Pod 里手动跑 migrate，看是否 IAM 通了 ====="
kubectl exec paas3-dbg -n $NS -- bash -c 'python manage.py migrate --no-input 2>&1 | grep -viE "InsecureKeyLength|DeprecationWarning|warnings.warn" | tail -25' 2>&1 | sed 's/^/    /'

echo ""
echo "===== 6. paas3 卡住 Pod 数量复查 ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'Init:' | wc -l | sed 's/^/  仍卡 Init 的 Pod 数: /'
