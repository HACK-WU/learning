#!/usr/bin/env bash
set -uo pipefail
{
MPOD=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-monitor-migrate-2' | awk '{print $1}' | head -1)
echo "POD=$MPOD"
echo ""

echo "===== 1. Pod 的容器列表 ====="
kubectl get pod "$MPOD" -n blueking -o jsonpath='{range .spec.initContainers[*]}init: {.name}{"\n"}{end}{range .spec.containers[*]}main: {.name}{"\n"}{end}' 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 2. 各 init 容器状态 ====="
kubectl get pod "$MPOD" -n blueking -o jsonpath='{range .status.initContainerStatuses[*]}{.name}{"  ready="}{.ready}{"  restart="}{.restartCount}{"  "}{.state.waiting.reason}{.state.terminated.reason}{"\n"}{end}' 2>/dev/null | sed 's/^/  /'

echo ""
for C in check-database db-migrate on-migrate; do
  echo "===== 3.$C init 容器日志（尾部 30 行）====="
  kubectl logs "$MPOD" -n blueking -c "$C" --tail=30 2>&1 | sed 's/^/  /'
  echo ""
done

echo "===== 4. 全量日志里搜 403 / GSE / streamto ====="
for C in check-database db-migrate on-migrate; do
  N=$(kubectl logs "$MPOD" -n blueking -c "$C" 2>/dev/null | grep -icE '403|streamto|permission|denied')
  echo "  $C: 匹配 $N 行"
done

echo ""
echo "===== 5. on-migrate 完整日志（找 GSE 调用点）====="
kubectl logs "$MPOD" -n blueking -c on-migrate 2>&1 | grep -iE '403|streamto|gse|error|fail|denied' | tail -25 | sed 's/^/  /'
} > /root/migrate-initlog.txt 2>&1
cat /root/migrate-initlog.txt
