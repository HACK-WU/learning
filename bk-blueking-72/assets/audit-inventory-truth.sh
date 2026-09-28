#!/usr/bin/env bash
echo "=== helm release 总数 ==="
helm list -n blueking --no-headers 2>/dev/null | wc -l

echo ""
echo "=== 节点 ==="
kubectl get nodes --no-headers 2>/dev/null

echo ""
echo "=== Pod 状态汇总 ==="
kubectl get pods -n blueking --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c

echo ""
echo "=== workloads ==="
printf "deploy=%s sts=%s ds=%s cj=%s\n" \
  "$(kubectl get deploy -n blueking --no-headers 2>/dev/null | wc -l)" \
  "$(kubectl get sts  -n blueking --no-headers 2>/dev/null | wc -l)" \
  "$(kubectl get ds   -n blueking --no-headers 2>/dev/null | wc -l)" \
  "$(kubectl get cj   -n blueking --no-headers 2>/dev/null | wc -l)"

echo ""
echo "=== deploy 副本为0（验后裁）数量 ==="
kubectl get deploy -n blueking --no-headers 2>/dev/null | awk '$2=="0/0"' | wc -l

echo ""
echo "=== helm release 名清单 ==="
helm list -n blueking --no-headers 2>/dev/null | awk '{print $1}' | sort

echo ""
echo "=== 内存 ==="
free -g | head -2
