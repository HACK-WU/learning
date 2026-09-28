#!/usr/bin/env bash
set -uo pipefail
NS=blueking
J=bkpaas3-apiserver-migrate-db-1

echo "===== 1. Job 的所有容器 ====="
kubectl get job $J -n $NS -o jsonpath='{range .spec.template.spec.containers[*]}  main: {.name}{"\n"}{end}' 2>&1
kubectl get job $J -n $NS -o jsonpath='{range .spec.template.spec.initContainers[*]}  init: {.name}{"\n"}{end}' 2>&1

echo ""
echo "===== 2. 每个容器的退出码（从备份的 Job 无法看，建一个探针起全部容器）====="
MP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep "^$J" | awk '{print $1}' | head -1)
if [ -n "$MP" ]; then
  kubectl get pod $MP -n $NS -o jsonpath='{range .status.containerStatuses[*]}  {.name}{"  ready="}{.ready}{"  exit="}{.state.terminated.exitCode}{"  reason="}{.state.terminated.reason}{"\n"}{end}' 2>&1
fi

echo ""
echo "===== 3. 逐个容器日志 ====="
for c in apiserver-db-migrate workloads-db-migrate apiserver-bkrepo-init; do
  echo "  --- $c ---"
  MP2=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep "^$J" | awk '{print $1}' | head -1)
  if [ -n "$MP2" ]; then
    kubectl logs $MP2 -n $NS -c $c 2>&1 | grep -viE 'InsecureKeyLength|Deprecation|warnings.warn|_jws|return self|fields\.E010|fields\.W342|fields\.W340|HINT:' | tail -18 | sed 's/^/    /'
  fi
done

echo ""
echo "===== 4. 若 Pod 已删：用 describe 看哪个容器 exit != 0 ====="
kubectl describe job $J -n $NS 2>&1 | grep -A5 'Events' | sed 's/^/    /'
