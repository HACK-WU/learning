#!/usr/bin/env bash
set -uo pipefail
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
{
echo "===== 决定性：apigateway 的 bk-gse 私钥能不能签出 GSE 认可的 token ====="
kubectl exec "$DP" -n blueking -- sh -c '
cd /app && python 2>&1 <<PY | tail -30
import os,sys,hashlib,datetime
sys.path.insert(0,"/app")
os.environ["DJANGO_SETTINGS_MODULE"]="apigateway.conf.default"
import django
django.setup()
from apigateway.core.models import Gateway
from apigateway.core.models import JWT as JWTModel

g=Gateway.objects.get(name="bk-gse")
j=JWTModel.objects.filter(gateway=g).first()

def norm(p):
    if not p: return ""
    if isinstance(p,bytes): p=p.decode("utf-8","ignore")
    return "".join(l.strip() for l in str(p).splitlines() if "BEGIN" not in l and "END" not in l)

pub = j.public_key
if isinstance(pub,bytes): pub=pub.decode("utf-8")
print("  bk-gse public_key md5 =", hashlib.md5(norm(pub).encode()).hexdigest())

epk = j.encrypted_private_key
print("  encrypted_private_key 长度 =", len(epk) if epk else 0)

# 尝试用项目自己的解密方式拿到私钥
priv = None
try:
    from apigateway.utils.crypto import KeyGenerator
    print("  KeyGenerator 可用")
except Exception as e:
    print("  KeyGenerator err:", e)

# apigateway 通常有 get_private_key 方法
for m in ["get_private_key","decrypt_private_key","private_key"]:
    if hasattr(j, m):
        print("  JWT 模型有方法/属性:", m)

try:
    getter = getattr(j, "get_private_key", None)
    if callable(getter):
        priv = getter()
        if isinstance(priv,bytes): priv=priv.decode("utf-8")
        print("  ✅ 通过 get_private_key() 取到私钥, len =", len(priv))
except Exception as e:
    print("  get_private_key 失败:", type(e).__name__, str(e)[:100])

if priv:
    import jwt
    payload={"iss":"APIGW","exp":int(datetime.datetime.now().timestamp())+900,"app":{},"user":{}}
    tok=jwt.encode(payload,priv,algorithm="RS512",headers={"kid":"apigw"})
    print("  ✅ 用 bk-gse 私钥签名成功(RS512)")
    gse=open("/tmp/gse_pub_check.pem").read()
    try:
        jwt.decode(tok,gse,algorithms=["RS512"])
        print("  ✅✅ 用 GSE 证书验：通过")
        print("  ===> 路径1(apigateway->GSE) 当前本来就是通的！")
    except Exception as e:
        print("  ❌ 用 GSE 证书验失败:", type(e).__name__)
        print("  ===> 路径1 也是坏的")
else:
    print("  ⚠️ 取不到私钥，无法完成签名验证")
PY
' 2>&1 | sed 's/^/  /'
} > /root/crit3.txt 2>&1
cat /root/crit3.txt
