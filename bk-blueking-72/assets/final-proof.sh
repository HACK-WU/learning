#!/usr/bin/env bash
set -uo pipefail
EP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-bk-esb-' | grep Running | awk '{print $1}' | head -1)
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
{
echo "===== 决定性验证：ESB 签名 → 用 GSE 公钥验，能否通过 ====="
kubectl exec "$EP" -n blueking -c bk-esb -- sh -c '
cd /app && python 2>&1 <<PY | tail -25
import os, sys, hashlib, datetime
sys.path.insert(0, "/app")
os.environ["DJANGO_SETTINGS_MODULE"] = "settings"
import django
django.setup()
import jwt
from esb.utils.jwt_utils import JWTKey

k = JWTKey()
pr = k.get_private_key()   # ESB 签发用私钥
pk_esb = k.get_public_key() # ESB 自己的公钥

# GSE 持有的公钥（从 GSE 容器取来比对）
gse_pub = open("/tmp/gse_pub.pem").read() if os.path.exists("/tmp/gse_pub.pem") else ""

def norm(p):
    if not p: return ""
    if isinstance(p, bytes): p = p.decode("utf-8","ignore")
    return "".join(l.strip() for l in str(p).splitlines() if "BEGIN" not in l and "END" not in l)

print("  ESB 签发私钥 len =", len(pr))
print("  ESB 公钥 md5 =", hashlib.md5(norm(pk_esb).encode()).hexdigest())

# 用 ESB 私钥按 ESB 的方式(RS512)签一个
payload = {"iss":"APIGW","exp":int(datetime.datetime.now().timestamp())+900,"app":{},"user":{}}
tok = jwt.encode(payload, pr, algorithm="RS512", headers={"kid":"apigw"})
print("  ✅ 用 ESB 私钥签名成功(RS512)")

# 用 ESB 自己的公钥验
try:
    jwt.decode(tok, pk_esb, algorithms=["RS512"])
    print("  ✅ 用 ESB 公钥验证: 通过")
except Exception as e:
    print("  ❌ 用 ESB 公钥验证失败:", e)

# 用 GSE 持有的公钥验
if gse_pub:
    print("  GSE 公钥 md5 =", hashlib.md5(norm(gse_pub).encode()).hexdigest())
    try:
        jwt.decode(tok, gse_pub, algorithms=["RS512"])
        print("  ✅ 用 GSE 公钥验证: 通过")
    except Exception as e:
        print("  ❌ 用 GSE 公钥验证失败:", type(e).__name__, str(e)[:80])
else:
    print("  (GSE 公钥文件未就绪)")
PY
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 先把 GSE 公钥拷到 ESB 容器供比对 ====="
kubectl exec "$GP" -n blueking -c bk-gse-data -- cat /data/gse/cert/apigw_jwt.crt 2>/dev/null > /tmp/gse_pub.pem
echo "  本地已存 GSE 公钥, md5=$(grep -v 'BEGIN\|END' /tmp/gse_pub.pem | tr -d '\n' | md5sum | awk '{print $1}')"
kubectl cp /tmp/gse_pub.pem blueking/"$EP":/tmp/gse_pub.pem -c bk-esb 2>&1 | sed 's/^/  /'
} > /root/final-proof.txt 2>&1
cat /root/final-proof.txt
