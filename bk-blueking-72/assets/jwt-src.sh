#!/usr/bin/env bash
set -uo pipefail
EP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-bk-esb-' | grep Running | awk '{print $1}' | head -1)
{
echo "===== 1. jwt_utils.py 完整源码（决定性）====="
kubectl exec "$EP" -n blueking -c bk-esb -- cat /app/esb/utils/jwt_utils.py 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. outgoing.py 里怎么拿到 private_key ====="
kubectl exec "$EP" -n blueking -c bk-esb -- grep -n -B8 -A8 "private_key\|jwt" /app/esb/outgoing.py 2>&1 | head -60 | sed 's/^/  /'

echo ""
echo "===== 3. gateway/helpers.py 里的 jwt 逻辑 ====="
kubectl exec "$EP" -n blueking -c bk-esb -- grep -n -B5 -A15 "jwt" /app/esb/gateway/helpers.py 2>&1 | head -60 | sed 's/^/  /'
} > /root/jwt-src.txt 2>&1
cat /root/jwt-src.txt
