#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 决定性核验：ESB 的 GSE 组件到底走不走 JWT ====="
EP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-bk-esb-' | grep Running | awk '{print $1}' | head -1)

echo "--- 1. gse_config_component.py 完整内容 ---"
kubectl exec "$EP" -n blueking -c bk-esb -- cat /app/components/bk/apisv2/gse/gse_config_component.py 2>&1 | sed 's/^/  /'

echo ""
echo "--- 2. configs.py 里的 host 定义 ---"
kubectl exec "$EP" -n blueking -c bk-esb -- cat /app/components/bk/apisv2/gse/toolkit/configs.py 2>&1 | sed 's/^/  /'

echo ""
echo "--- 3. 这些组件是否 with_jwt_header ---"
kubectl exec "$EP" -n blueking -c bk-esb -- grep -rn 'with_jwt_header' /app/components/ 2>/dev/null | head -10 | sed 's/^/  /'

echo ""
echo "===== 4. 谁在用 with_jwt_header=True（真正的 JWT 调用方）====="
kubectl exec "$EP" -n blueking -c bk-esb -- grep -rln 'with_jwt_header=True' /app/components/ 2>/dev/null | head -15 | sed 's/^/  /'
} > /root/recheck.txt 2>&1
cat /root/recheck.txt
