#!/usr/bin/env bash
set -uo pipefail
NS=blueking
J=bkpaas3-apiserver-migrate-db-1

echo "===== 轮询等 apiserver-bkrepo-init 结束 ====="
for i in $(seq 1 90); do
  MP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep "^$J" | awk '{print $1}' | head -1)
  if [ -z "$MP" ]; then
    echo "  Pod 已消失（第${i}轮）"
    kubectl describe job $J -n $NS 2>&1 | grep -E 'Backoff|Failed|Deadline' | tail -5 | sed 's/^/    /'
    exit 0
  fi
  ST=$(kubectl get pod $MP -n $NS -o jsonpath='{range .status.containerStatuses[*]}{.name}{"|"}{.state.terminated.exitCode}{"|"}{.state.terminated.reason}{"\n"}{end}' 2>/dev/null)
  BK=$(echo "$ST" | grep 'apiserver-bkrepo-init')
  if echo "$BK" | grep -qE '\|[0-9]+\|'; then
    CODE=$(echo "$BK" | cut -d'|' -f2)
    echo "  apiserver-bkrepo-init 退出码 = $CODE"
    echo "  ===== 日志 ====="
    kubectl logs $MP -n $NS -c apiserver-bkrepo-init 2>&1 | grep -viE 'InsecureKey|Deprecat|warnings.warn|_jws|return self' | tail -30 | sed 's/^/    /'
    exit 0
  fi
  sleep 3
done

echo "  超时未见终态"
kubectl describe job $J -n $NS 2>&1 | tail -8 | sed 's/^/    /'
