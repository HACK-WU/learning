#!/usr/bin/env bash
set -uo pipefail
{
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
CP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-core-api' | grep Running | awk '{print $1}' | head -1)
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)

echo "===== 1. GSE 容器内证书内容（前几行）====="
kubectl exec "$GP" -n blueking -- head -3 /data/gse/cert/apigw_jwt.crt 2>&1 | sed 's/^/  /'
kubectl exec "$GP" -n blueking -- md5sum /data/gse/cert/apigw_jwt.crt 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. apigateway 里 bk-gse 的 JWT 公钥（DB 查）====="
kubectl exec "$DP" -n blueking -- sh -c '
python manage.py shell <<PY 2>/dev/null
from apigateway.core.models import Gateway
from apigateway.core.models import JWT
import hashlib
g = Gateway.objects.filter(name="bk-gse").first()
print("  gateway id:", g.id, "name:", g.name)
try:
    from apigateway.core.models import GatewayJWT
    print("  GatewayJWT count:", GatewayJWT.objects.filter(gateway=g).count())
except Exception as e:
    print("  GatewayJWT err:", e)
# 尝试拿 public key
for attr in ["_public_key", "public_key", "jwt_public_key"]:
    if hasattr(g, attr):
        v = getattr(g, attr)
        if v:
            print("  ", attr, "md5:", hashlib.md5(str(v).encode()).hexdigest())
PY
' 2>&1 | sed 's/^/  /' | head -12

echo ""
echo "===== 3. 核心验证：用 core-api 接口拿 bk-gse 公钥并比对 ====="
echo "  --- core-api 容器内 curl（它有 curl 或 wget?）---"
kubectl exec "$CP" -n blueking -- sh -c 'command -v curl wget python3 2>&1 | head -3' 2>&1 | sed 's/^/  /'

echo ""
echo "  --- 起临时 Pod 从集群内访问 core-api 拿公钥 ---"
kubectl delete pod keycheck -n blueking --ignore-not-found --wait=false 2>/dev/null
kubectl run keycheck -n blueking --image=hub.bktencent.com/library/busybox:1.34.0 --restart=Never --command -- sleep 600 2>&1 | tail -1
for i in $(seq 1 30); do
  [ "$(kubectl get pod keycheck -n blueking -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ] && break
  sleep 2
done
kubectl exec keycheck -n blueking -- sh -c '
  echo "  解析 core-api:"
  nslookup bk-apigateway-core-api 2>&1 | grep -E "Address|Name" | head -4
  echo "  取公钥:"
  wget -q -O- "http://bk-apigateway-core-api/api/v1/open/gateways/bk-gse/public_key/" 2>&1 | head -c 300
  echo ""
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 4. 清理 ====="
kubectl delete pod keycheck -n blueking --ignore-not-found --wait=false 2>&1 | sed 's/^/  /'
} > /root/jwt-verify.txt 2>&1
cat /root/jwt-verify.txt
