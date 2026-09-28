#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 关键验证：apigateway 是否也直接调 GSE？ ====="
echo "  若 apigateway 也调 GSE（用 bk-gse 私钥签），则改 GSE 证书会破坏这条路径"
echo ""

echo "===== 1. ESB 里 GSE component 的后端地址 ====="
EP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-bk-esb-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$EP" -n blueking -c bk-esb -- sh -c '
grep -rn "gse" /app/components/generic/apis/ 2>/dev/null | head -5
echo "  --- component 定义 ---"
find /app -path "*gse*" -name "*.py" 2>/dev/null | head -8
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. apigateway 里 bk-gse gateway 的后端（是否有 upstream）====="
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$DP" -n blueking -- sh -c '
cd /app && python 2>&1 <<PY | tail -20
import os,sys
sys.path.insert(0,"/app")
os.environ["DJANGO_SETTINGS_MODULE"]="apigateway.conf.default"
import django
django.setup()
from apigateway.core.models import Gateway, Stage, Backend
try:
    g=Gateway.objects.get(name="bk-gse")
    print("  gateway bk-gse id:",g.id," is_public:",g.is_public)
    for s in Stage.objects.filter(api=g):
        print("   stage:",s.name)
    for b in Backend.objects.filter(api=g):
        print("   backend:",b.name," host:",b.config.get("hosts") if hasattr(b,"config") else "?")
except Exception as e:
    print("  err:",e)
PY
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. 决定性证据：GSE 的 403 是否只针对 ESB 来的请求 ====="
echo "  之前实测：无认证头也 403 -> 说明 GSE 一律验签"
echo "  但需确认 apigateway 直连 GSE 是否成功过"

echo ""
echo "===== 4. ESB 转发 GSE 时的目标地址 ====="
kubectl exec "$EP" -n blueking -c bk-esb -- sh -c '
grep -rn -iE "gse.*host|dataroute|add_streamto" /app/components/ 2>/dev/null | head -8
' 2>&1 | sed 's/^/  /'
} > /root/verify-a.txt 2>&1
cat /root/verify-a.txt
