#!/usr/bin/env bash
set -uo pipefail
{
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)

echo "===== 1. 密钥一致已确认，查 api_id=9 是哪个 gateway ====="
kubectl exec "$DP" -n blueking -- sh -c '
python manage.py shell <<PY 2>&1 | tail -12
from apigateway.core.models import API, Gateway
a = API.objects.filter(id=9).first()
print("api_id=9:", a.name if a else "?", "gateway=", a.gateway.name if a and a.gateway else "?")
g = Gateway.objects.filter(name="bk-gse").first()
print("bk-gse gateway id:", g.id if g else "?")
if g:
    for api in API.objects.filter(gateway=g):
        print("   api:", api.id, api.name)
PY
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. 关键：GSE 校验什么（ESB 传的 JWT 是谁签的）====="
echo "  403 报错来自 bk-gse-data:59702/dataroute/v1/add_streamto"
echo "  ESB 转发时带的 JWT 是 apigw 用 bk-gse 私钥签的"
echo "  GSE 用 apigw_jwt.crt 验 -> 密钥一致却仍 invalid signature"
echo "  --> 怀疑：JWT 过期 / issuer 不匹配 / 算法不一致"

echo ""
echo "===== 3. 查 GSE data 的完整 403 日志（含 jwt 细节）====="
kubectl logs "$GP" -n blueking --tail=500 2>/dev/null | grep -iE 'jwt|signature|403|verify' | tail -20 | sed 's/^/  /'

echo ""
echo "===== 4. GSE 期望的 issuer/算法（容器内配置）====="
kubectl exec "$GP" -n blueking -- sh -c '
  echo "  --- 找 gse 配置文件 ---"
  find /data/gse -maxdepth 3 -iname "*.conf" -o -maxdepth 3 -iname "*.ini" -o -maxdepth 3 -iname "*.yaml" 2>/dev/null | head -10
  echo "  --- 搜 jwt 相关配置 ---"
  grep -rsiE "jwt|issuer|algorithm" /data/gse/cert/ 2>/dev/null | head -8
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 5. 解密一个真实的 JWT 看 payload ====="
kubectl exec "$DP" -n blueking -- sh -c '
python manage.py shell <<PY 2>&1 | tail -15
from apigateway.core.models import Gateway
import base64, json
g = Gateway.objects.filter(name="bk-gse").first()
if g:
    print("gateway name:", g.name, "id:", g.id)
    print("is_public:", getattr(g,"is_public",None), "status:", getattr(g,"status",None))
PY
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 6. 时间同步检查（JWT 过期常见原因）====="
echo "  WSL 时间: $(date '+%F %T %Z')"
echo "  --- 容器时间 ---"
kubectl exec "$GP" -n blueking -- date '+%F %T %Z' 2>&1 | sed 's/^/  GSE: /'
kubectl exec "$DP" -n blueking -- date '+%F %T %Z' 2>&1 | sed 's/^/  APIGW: /'
} > /root/jwt-real.txt 2>&1
cat /root/jwt-real.txt
