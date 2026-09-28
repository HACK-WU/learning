#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 关键：403 到底来自哪条路径？ ====="
echo ""
echo "  两条路径已确认都存在："
echo "  路径1: 调用方 -> apigateway(bk-gse) -> GSE   签=0e18be8a  验=0e18be8a  ✅应通过"
echo "  路径2: 调用方 -> ESB -> GSE                  签=0e82d670  验=0e18be8a  ❌失败"
echo ""

echo "--- 1. 之前实测 403 的那个请求，走的是哪条路？ ---"
echo "  回顾：之前是直接 curl GSE 服务(bk-gse-data:59702)，带/不带认证头都 403"
echo "  -> 直接 curl = 自己造的请求，不属于任何一条路径"
echo "  -> 无认证头 403 是正常的（GSE 要求 JWT）"
echo ""

echo "--- 2. 真正的生产调用方是谁？ ---"
echo "  之前查到：ESB 日志 60 次 GSE 调用全部来自 bk_monitorv3"
echo "  -> monitor 走 ESB？还是 apigateway？"
echo ""

echo "--- 3. 决定性：monitor 调 GSE 的配置 ---"
kubectl get cm bk-monitor-monitor-env -n blueking -o jsonpath='{.data}' 2>/dev/null | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    for k,v in sorted(d.items()):
        if any(x in k.upper() for x in ["GSE","BKAPI","APIGW","ESB","NODEMAN"]):
            print("   %s = %s" % (k,v))
except Exception as e: print("  err:",e)
' 2>&1 | sed 's/^/  /'

echo ""
echo "--- 4. 决定性：用 apigateway 的 bk-gse 私钥签，GSE 能通过吗？ ---"
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$DP" -n blueking -- sh -c '
cd /app && python 2>&1 <<PY | tail -25
import os,sys,hashlib,datetime
sys.path.insert(0,"/app")
os.environ["DJANGO_SETTINGS_MODULE"]="apigateway.conf.default"
import django
django.setup()
import jwt
from apigateway.core.models import Gateway, JWT as JWTModel
g=Gateway.objects.get(name="bk-gse")
j=JWTModel.objects.filter(gateway=g).first()
if j and j.private_key:
    priv=j.private_key
    if isinstance(priv,bytes): priv=priv.decode("utf-8")
    print("  bk-gse 私钥 len =",len(priv))
    payload={"iss":"APIGW","exp":int(datetime.datetime.now().timestamp())+900,"app":{},"user":{}}
    tok=jwt.encode(payload,priv,algorithm="RS512",headers={"kid":"apigw"})
    print("  ✅ 用 bk-gse 私钥签名成功")
    # 用 GSE 证书验
    gse=open("/tmp/gse_pub_check.pem").read() if os.path.exists("/tmp/gse_pub_check.pem") else ""
    if gse:
        try:
            jwt.decode(tok,gse,algorithms=["RS512"])
            print("  ✅ 用 GSE 证书验：通过 -> 路径1 本来就是通的")
        except Exception as e:
            print("  ❌ 用 GSE 证书验失败:",e)
else:
    print("  bk-gse 无私钥或不可读")
PY
' 2>&1 | sed 's/^/  /'
} > /root/crit.txt 2>&1
cat /root/crit.txt
