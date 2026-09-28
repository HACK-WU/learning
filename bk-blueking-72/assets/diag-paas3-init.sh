#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. paas3 web 的 initContainer 状态 ====="
P=bkpaas3-apiserver-web-b646d4bf9-wn7h2
kubectl get pod $P -n $NS -o jsonpath='{range .status.initContainerStatuses[*]}{"  init: "}{.name}{"  ready="}{.ready}{"  reason="}{.state.waiting.reason}{"\n"}{end}' 2>&1

echo ""
echo "===== 2. initContainer 日志（真实报错）====="
kubectl logs $P -n $NS -c $(kubectl get pod $P -n $NS -o jsonpath='{.spec.initContainers[0].name}' 2>/dev/null) --tail=25 2>&1 | sed 's/^/    /'

echo ""
echo "===== 3. 所有 paas3 的 Job 完成情况（init 链依赖）====="
kubectl get jobs -n $NS --no-headers 2>/dev/null | grep bkpaas3 | awk '{printf "  %-48s %-10s\n", $1, $2}'

echo ""
echo "===== 4. migrate-db Pod 到底怎么样了 ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'migrate-db' | grep paas3 | awk '{printf "  %-48s %-12s 重启%s\n", $1, $3, $4}'
MP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkpaas3-apiserver-migrate-db' | awk '{print $1}' | head -1)
[ -n "$MP" ] && { echo "  --- $MP 日志 ---"; kubectl logs $MP -n $NS --tail=25 2>&1 | sed 's/^/    /'; }

echo ""
echo "===== 5. init-data / init-devops 日志（也在 Init）====="
for p in bkpaas3-apiserver-init-data-1-mlzk6 bkpaas3-apiserver-init-devops-1-q9swb; do
  [ -n "$p" ] && { echo "  --- $p ---"; kubectl logs $p -n $NS --tail=12 2>&1 | sed 's/^/    /'; }
done

echo ""
echo "===== 6. apigw sync 类新报错（DNS 修好后换错没）====="
for p in bkiam-saas-apigateway-sync-1-4gs4j bkiam-saas-synchronization-1-zxk9q bk-cmdb-apigw-1-grp4l; do
  echo "  --- $p ---"
  kubectl logs $p -n $NS --tail=8 2>&1 | grep -viE '^\s*$' | tail -5 | sed 's/^/    /'
done
