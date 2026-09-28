#!/usr/bin/env bash
NS=blueking
echo "=== STEP 1: 启动监控数据面（依赖 kafka，先起这批） ==="
for d in bk-monitor-transfer-default bk-monitor-ingester bk-monitor-unify-query bk-monitor-api; do
  cur=$(kubectl get deploy -n $NS $d -o jsonpath='{.spec.replicas}' 2>/dev/null)
  if [ "$cur" == "0" ]; then
    kubectl scale deploy -n $NS $d --replicas=1 >/dev/null 2>&1 && echo "  [起] $d"
  else
    echo "  [已在] $d ($cur)"
  fi
done

echo ""
echo "=== STEP 2: 等 90s ==="
sleep 90

echo ""
echo "=== STEP 3: 副本状态 ==="
for d in bk-monitor-transfer-default bk-monitor-ingester bk-monitor-unify-query bk-monitor-api bk-monitor-influxdb-proxy bk-monitor-prom-agg-gateway; do
  kubectl get deploy -n $NS $d --no-headers 2>/dev/null | awk '{printf "  %-40s %s\n",$1,$2}'
done

echo ""
echo "=== STEP 4: 启动监控 web 层 ==="
for d in bk-monitor-web bk-monitor-web-query-api bk-monitor-grafana bk-monitor-healthz bk-monitor-web-worker bk-monitor-web-beat; do
  cur=$(kubectl get deploy -n $NS $d -o jsonpath='{.spec.replicas}' 2>/dev/null)
  echo "  $d : $cur"
done

echo ""
echo "=== STEP 5: 内存 ==="
free -g | sed -n '1,2p'
