#!/usr/bin/env bash
set -uo pipefail
{
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)

echo "===== 1. GSE 容器内证书的指纹 ====="
kubectl exec "$GP" -n blueking -- sh -c '
  if command -v openssl >/dev/null 2>&1; then
    echo "  --- openssl 可用 ---"
    openssl x509 -in /data/gse/cert/apigw_jwt.crt -noout -subject -dates 2>&1 | head -5
    openssl x509 -in /data/gse/cert/apigw_jwt.crt -noout -pubkey 2>/dev/null | openssl md5
  else
    echo "  --- openssl 不可用，用 md5 ---"
    md5sum /data/gse/cert/apigw_jwt.crt
    wc -c /data/gse/cert/apigw_jwt.crt
  fi
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. helmfile 里 bk-gse 的 publicKeyBase64 指纹 ====="
echo "  --- 从 values 渲染出的公钥（脱敏：只取长度+首尾+md5）---"
grep -A2 'builtinGateway' /root/bk72/install/blueking/environments/default/values.yaml 2>/dev/null | head -5 | sed 's/^/    /'
echo "  --- 公钥定义所在文件 ---"
grep -rln 'publicKeyBase64' /root/bk72/install/blueking/environments/ 2>/dev/null | head -5 | sed 's/^/    /'

echo ""
echo "===== 3. 关键：GSE release 状态是 failed！ ====="
helm list -A 2>/dev/null | grep -E 'bk-gse|bk-apigateway' | sed 's/^/  /'

echo ""
echo "===== 4. GSE release failed 的原因（helm 记录）====="
helm history bk-gse -n blueking --max 5 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 5. 网关 bk-gse gateway 的 JWT 密钥对（从 dashboard DB 查）====="
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$DP" -n blueking -- sh -c '
python manage.py shell <<PY 2>/dev/null
from apigateway.core.models import Gateway
g = Gateway.objects.filter(name="bk-gse").first()
if g:
    print("  gateway:", g.name, "status:", g.status, "is_public:", g.is_public)
    try:
        k = g.jwt_crypto if hasattr(g,"jwt_crypto") else None
        print("  jwt algo:", getattr(g, "jwt_algorithm", None))
    except Exception as e:
        print("  err:", e)
PY
' 2>&1 | sed 's/^/  /' | head -10

echo ""
echo "===== 6. 时间线：GSE 与 apigateway 谁先装 ====="
helm list -A 2>/dev/null | awk 'NR==1 || /bk-gse|bk-apigateway/' | sed 's/^/  /'
} > /root/jwt-compare.txt 2>&1
cat /root/jwt-compare.txt
