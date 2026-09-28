#!/usr/bin/env bash
set -uo pipefail
{
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)

echo "===== 1. 生成一个真实 JWT，看 header 的算法 ====="
kubectl exec "$DP" -n blueking -- sh -c '
python manage.py shell <<PY 2>&1 | tail -25
import json, base64
from apigateway.core.models import Gateway
from apigateway.core.signing import *
g = Gateway.objects.filter(name="bk-gse").first()
# 找一个可用的 JWT 生成函数
import apigateway.core.utils as U
funcs=[f for f in dir(U) if "jwt" in f.lower()]
print("core.utils 里 jwt 相关:", funcs)
try:
    from apigateway.core.jwt import *
    print("core.jwt 模块函数:", [f for f in dir() if "sign" in f.lower() or "encode" in f.lower()])
except Exception as e:
    print("core.jwt err:", e)
# 直接看 gateway 的 jwt 配置
print("gateway attrs:", [a for a in dir(g) if "jwt" in a.lower()])
for a in [x for x in dir(g) if "jwt" in x.lower()]:
    v=getattr(g,a)
    if not callable(v):
        print("  ", a, "=", str(v)[:200])
PY
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. GSE 侧期望的算法 ====="
kubectl exec "$GP" -n blueking -c bk-gse-data -- sh -c '
  echo "  --- 查 gse_data.conf 里的 jwt/alg ---"
  grep -iE "jwt|alg|rsa|sign" /data/gse/etc/gse_data.conf 2>/dev/null | head -10
  echo "  --- 证书算法 ---"
  head -1 /data/gse/cert/apigw_jwt.crt
  echo "  --- 密钥长度（bit）---"
  grep -v "BEGIN\|END" /data/gse/cert/apigw_jwt.crt | tr -d "\n" | base64 -d 2>/dev/null | wc -c
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. ESB 转发时带的 JWT 是谁签的（关键）====="
echo "  ESB 日志显示 req_app_code=bk_monitorv3"
echo "  --> 若 ESB 用 bk_monitorv3 的密钥签，而 GSE 用 bk-gse 公钥验 -> 必然 invalid signature"
echo "  --- 查 bk_monitorv3 是否也是 gateway ---"
kubectl exec "$DP" -n blueking -- sh -c '
python manage.py shell <<PY 2>&1 | tail -8
from apigateway.core.models import Gateway
qs=Gateway.objects.all()
print("  全部 gateway:", [g.name for g in qs])
PY
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 4. ESB 侧配置：转发时用哪个 app 的 jwt ====="
kubectl exec -n blueking "$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-bk-esb-' | grep Running | awk '{print $1}' | head -1)" -- sh -c '
  env | grep -iE "jwt|app_code|secret|gateway" | head -12
' 2>&1 | sed 's/^/  /'
} > /root/alg-check.txt 2>&1
cat /root/alg-check.txt
