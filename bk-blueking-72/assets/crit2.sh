#!/usr/bin/env bash
set -uo pipefail
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
{
echo "===== 决定性：apigateway 的 bk-gse 私钥 vs GSE 证书，是否一对 ====="

echo "--- 1. 先看 JWT 表有哪些字段 ---"
kubectl exec "$DP" -n blueking -- sh -c '
cd /app && python 2>&1 <<PY | tail -12
import os,sys
sys.path.insert(0,"/app")
os.environ["DJANGO_SETTINGS_MODULE"]="apigateway.conf.default"
import django
django.setup()
from apigateway.core.models import JWT as M
print("  JWT 模型字段:")
for f in M._meta.get_fields():
    print("   -",f.name)
PY
' 2>&1 | sed 's/^/  /'

echo ""
echo "--- 2. 用 bk-gse 的密钥自签自验（确认密钥可用）---"
kubectl exec "$GP" -n blueking -c bk-gse-data -- cat /data/gse/cert/apigw_jwt.crt > /tmp/gse_pub_check.pem 2>/dev/null
echo "  GSE 证书已取, md5=$(grep -v 'BEGIN\|END' /tmp/gse_pub_check.pem | tr -d '\n' | md5sum | awk '{print $1}')"
kubectl cp /tmp/gse_pub_check.pem blueking/"$DP":/tmp/gse_pub_check.pem 2>&1 | sed 's/^/  /'

kubectl exec "$DP" -n blueking -- sh -c '
cd /app && python 2>&1 <<PY | tail -25
import os,sys,hashlib,datetime
sys.path.insert(0,"/app")
os.environ["DJANGO_SETTINGS_MODULE"]="apigateway.conf.default"
import django
django.setup()
import jwt
from apigateway.core.models import Gateway
from apigateway.core.models import JWT as JWTModel
g=Gateway.objects.get(name="bk-gse")
j=JWTModel.objects.filter(gateway=g).first()
print("  JWT 记录存在:", bool(j))
if j:
    for attr in ["public_key","private_key"]:
        v=getattr(j,attr,None)
        if v is None:
            print("   ",attr,"= None")
        else:
            if isinstance(v,bytes): v=v.decode("utf-8","ignore")
            print("   ",attr,"len =",len(v))
PY
' 2>&1 | sed 's/^/  /'
} > /root/crit2.txt 2>&1
cat /root/crit2.txt
