#!/usr/bin/env bash
set -uo pipefail
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
{
echo "===== 1. 官方同步命令 sync_esb_jwt_key_to_gateway.py ====="
kubectl exec "$DP" -n blueking -- cat /app/apigateway/apps/esb/management/commands/sync_esb_jwt_key_to_gateway.py 2>&1 | sed 's/^/  /' | head -70

echo ""
echo "===== 2. create_esb_jwt_key.py ====="
kubectl exec "$DP" -n blueking -- cat /app/apigateway/apps/esb/management/commands/create_esb_jwt_key.py 2>&1 | sed 's/^/  /' | head -50

echo ""
echo "===== 3. 该命令是否在 helm chart 里被调用 ====="
rm -rf /tmp/apigwchart2 && mkdir -p /tmp/apigwchart2
helm pull blueking/bk-apigateway --version 1.13.28 --destination /tmp/apigwchart2 --untar 2>&1 | head -2
grep -rn 'sync_esb_jwt_key_to_gateway\|create_esb_jwt_key' /tmp/apigwchart2/ 2>/dev/null | head -10 | sed 's/^/  /'
} > /root/sync-cmd.txt 2>&1
cat /root/sync-cmd.txt
