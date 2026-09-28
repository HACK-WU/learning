#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. 路径1 是否真有流量（apigateway -> bk-gse gateway）====="
echo "  --- apigateway 里 bk-gse 的访问记录 ---"
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
AP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-api-' | grep Running | awk '{print $1}' | head -1)
echo "  dashboard=$DP  api=$AP"

kubectl exec "$DP" -n blueking -- sh -c '
cd /app && python 2>&1 <<PY | tail -20
import os,sys
sys.path.insert(0,"/app")
os.environ["DJANGO_SETTINGS_MODULE"]="apigateway.conf.default"
import django
django.setup()
from apigateway.core.models import Gateway
g=Gateway.objects.get(name="bk-gse")
print("  bk-gse gateway id:",g.id," is_public:",g.is_public," status:",g.status)
PY
' 2>&1 | sed 's/^/  /'

echo ""
echo "  --- apigateway-api 日志里有没有 bk-gse 的请求 ---"
kubectl logs "$AP" -n blueking --tail=300 2>/dev/null | grep -io 'gse[a-z_]*' | sort | uniq -c | sort -rn | head -8 | sed 's/^/  /'

echo ""
echo "===== 2. GSE 当前是否仍是 403（基线）====="
kubectl exec -n blueking deploy/bk-gse-data -c bk-gse-data -- sh -c '
curl -s -o /dev/null -w "  HTTP=%{http_code}\n" http://127.0.0.1:59702/api/v1/healthz 2>&1
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. 准备合并公钥（bk-gse + ESB 并存）====="
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$GP" -n blueking -c bk-gse-data -- cat /data/gse/cert/apigw_jwt.crt > /tmp/gse_cur.crt 2>/dev/null
echo "  当前 GSE 证书 (bk-gse 公钥) md5 = $(grep -v 'BEGIN\|END' /tmp/gse_cur.crt | tr -d '\n' | md5sum | awk '{print $1}')"

# ESB 公钥
DP2="$DP"
kubectl exec "$DP2" -n blueking -- sh -c 'base64 -w0 /tmp/esb_pub.pem' > /tmp/esb_pub.b64raw 2>/dev/null
tr -d '\n' < /tmp/esb_pub.b64raw > /tmp/esb_pub.b64
base64 -d /tmp/esb_pub.b64 > /tmp/esb_pub.pem 2>/dev/null
echo "  ESB 公钥 md5 = $(grep -v 'BEGIN\|END' /tmp/esb_pub.pem | tr -d '\n' | md5sum | awk '{print $1}')"

# 合并
cat /tmp/gse_cur.crt > /tmp/combined.crt
echo "" >> /tmp/combined.crt
cat /tmp/esb_pub.pem >> /tmp/combined.crt
echo "  合并后 PEM 块数 = $(grep -c 'BEGIN' /tmp/combined.crt)"
base64 -w0 /tmp/combined.crt > /tmp/combined.b64
echo "  合并后 base64 长度 = $(wc -c < /tmp/combined.b64)"
} > /root/a1.txt 2>&1
cat /root/a1.txt
