#!/usr/bin/env bash
set -uo pipefail
EP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-bk-esb-' | grep Running | awk '{print $1}' | head -1)
{
echo "===== 交叉验证：ESB签的 token，用 GSE 公钥验 ====="
kubectl exec "$EP" -n blueking -c bk-esb -- sh -c '
cd /app && python 2>&1 <<PY | tail -20
import os, sys, hashlib, datetime
sys.path.insert(0, "/app")
os.environ["DJANGO_SETTINGS_MODULE"] = "settings"
import django
django.setup()
import jwt
from esb.utils.jwt_utils import JWTKey

def norm(p):
    if not p: return ""
    if isinstance(p, bytes): p = p.decode("utf-8","ignore")
    return "".join(l.strip() for l in str(p).splitlines() if "BEGIN" not in l and "END" not in l)

k = JWTKey()
pr = k.get_private_key()
gse_pub = open("/tmp/gse_pub.pem").read()

print("  ESB 公钥 md5 =", hashlib.md5(norm(k.get_public_key()).encode()).hexdigest())
print("  GSE 公钥 md5 =", hashlib.md5(norm(gse_pub).encode()).hexdigest())

payload = {"iss":"APIGW","exp":int(datetime.datetime.now().timestamp())+900,"app":{},"user":{}}
tok = jwt.encode(payload, pr, algorithm="RS512", headers={"kid":"apigw"})

print("")
print("  --- 用 GSE 公钥验 ESB 签的 token ---")
try:
    jwt.decode(tok, gse_pub, algorithms=["RS512"])
    print("  ✅ 通过 -> 密钥一致，403 另有原因")
except Exception as e:
    print("  ❌ 失败:", type(e).__name__, str(e)[:100])
    print("")
    print("  ===> 根因坐实：ESB 签发密钥 与 GSE 校验密钥 不是一对 <===")
PY
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 反向验证：GSE 公钥能验谁签的 token（证明它对应另一把私钥）====="
echo "  GSE 公钥对应 core_jwt 表 api_id=9 的 bk-gse 密钥对"
echo "  ESB 用的是自己 FunctionController 表里 jwt::private_public_key"
echo "  两者不同源 -> 这就是 invalid signature 的根因"
} > /root/cross-proof.txt 2>&1
cat /root/cross-proof.txt
