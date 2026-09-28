#!/usr/bin/env bash
set -uo pipefail
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
{
echo "===== 最终对照：ESB 公钥 vs 各 gateway 公钥 ====="
kubectl exec "$DP" -n blueking -- sh -c '
cd /app && python 2>&1 <<PY | tail -30
import os, sys, hashlib
sys.path.insert(0,"/app")
os.environ["DJANGO_SETTINGS_MODULE"]="apigateway.conf.default"
import django
django.setup()
from apigateway.apps.esb.bkcore.models import FunctionController
from apigateway.core.models import Gateway, JWT

def norm(p):
    if not p: return ""
    if isinstance(p, bytes): p=p.decode("utf-8","ignore")
    return "".join(l.strip() for l in str(p).splitlines() if "BEGIN" not in l and "END" not in l)

k = FunctionController.objects.get_jwt_key() or {}
esb_pub = k.get("public_key","")
esb_md5 = hashlib.md5(norm(esb_pub).encode()).hexdigest()
print("  ESB 签发公钥 md5 =", esb_md5)
print("")
print("  --- 各 gateway 的 JWT 公钥 ---")
seen = {}
for j in JWT.objects.all():
    try:
        g = j.gateway
        gname = g.name if g else "?"
    except Exception:
        gname = "?"
    m = hashlib.md5(norm(j.public_key).encode()).hexdigest()
    seen[gname] = m

for gname in sorted(seen):
    m = seen[gname]
    tags = ""
    if m == esb_md5: tags += "  <== 与ESB一致"
    if m == "0e18be8a0f385db7ba21c81b58fcc265": tags += "  <== GSE持有"
    print("   %-16s %s%s" % (gname, m, tags))

print("")
print("  --- 结论判定 ---")
if "bk-gse" in seen:
    g = seen["bk-gse"]
    if g == esb_md5:
        print("   bk-gse 公钥 == ESB 公钥 -> 密钥一致，403 另有原因")
    else:
        print("   bk-gse 公钥 != ESB 公钥")
        print("   -> ESB 用自己密钥签名，GSE 用 bk-gse 公钥验 -> 必然 invalid signature")
        print("   -> 根因坐实：ESB 密钥未同步给 bk-gse gateway")
else:
    print("   !!! bk-gse 没有 JWT 记录")
PY
' 2>&1 | sed 's/^/  /'
} > /root/final-map.txt 2>&1
cat /root/final-map.txt
