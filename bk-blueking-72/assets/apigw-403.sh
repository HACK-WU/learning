#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. apigateway 各组件日志里搜 gse / streamto / 403 ====="
for P in $(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'apigateway-(core-api|apigateway|bk-esb)-' | grep Running | awk '{print $1}'); do
  N=$(kubectl logs "$P" -n blueking --tail=3000 2>/dev/null | grep -icE 'streamto|bk-gse')
  echo "  $P : 匹配 $N 行"
done

echo ""
echo "===== 2. core-api 日志里的 gse/403 片段 ====="
CP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-core-api' | grep Running | awk '{print $1}' | head -1)
echo "  POD=$CP"
kubectl logs "$CP" -n blueking --tail=3000 2>/dev/null | grep -iE 'streamto|bk-gse|403' | tail -20 | sed 's/^/  /'

echo ""
echo "===== 3. ESB 组件日志（我上轮说不存在，实际在运行）====="
EP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-bk-esb-' | grep Running | awk '{print $1}' | head -1)
echo "  POD=$EP"
kubectl logs "$EP" -n blueking --tail=2000 2>/dev/null | grep -iE 'streamto|gse|403' | tail -20 | sed 's/^/  /'

echo ""
echo "===== 4. bk-esb 是什么（确认其功能）====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -i 'esb' | sed 's/^/  /'

echo ""
echo "===== 5. 网关里 bk-gse 这个 gateway 是否存在 ====="
kubectl exec -n blueking "$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)" -- \
  sh -c 'python manage.py shell -c "
from apigateway.core.models import Gateway
for g in Gateway.objects.all().values(\"name\",\"status\",\"is_public\")[:40]:
    print(g)
"' 2>&1 | grep -iE 'gse|monitor|name' | head -25 | sed 's/^/  /'
} > /root/apigw-403.txt 2>&1
cat /root/apigw-403.txt
