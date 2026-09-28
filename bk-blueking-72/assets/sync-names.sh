#!/usr/bin/env bash
set -uo pipefail
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
{
echo "===== 决定性：SYNC_ESB_JWT_KEY_GATEWAY_NAMES 包含哪些 gateway ====="
kubectl exec "$DP" -n blueking -- sh -c '
cd /app && python 2>&1 <<PY | tail -25
import os, sys, hashlib
sys.path.insert(0,"/app")
os.environ["DJANGO_SETTINGS_MODULE"]="apigateway.conf.default"
import django
django.setup()
from django.conf import settings
names = getattr(settings, "SYNC_ESB_JWT_KEY_GATEWAY_NAMES", None)
print("  SYNC_ESB_JWT_KEY_GATEWAY_NAMES =", names)
print("")
print("  是否包含 bk-gse:", ("bk-gse" in (names or [])) if names else "N/A")
PY
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 备用：直接从配置文件搜该设置 ====="
kubectl exec "$DP" -n blueking -- grep -rn 'SYNC_ESB_JWT_KEY_GATEWAY_NAMES' /app/apigateway/conf/ 2>/dev/null | head -5 | sed 's/^/  /'

echo ""
echo "===== 核心结论所需：ESB 公钥 vs 各 gateway 公钥对照 ====="
kubectl exec "$DP" -n blueking -- sh -c '
cd /app && python 2>&1 <<PY | tail -20
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
print("  ESB 签发公钥        md5 =", hashlib.md5(norm(esb_pub).encode()).hexdigest())
print("")
print("  --- 各 gateway 的公钥 ---")
for j in JWT.objects.all().select_related("api"):
    try:
        gname = j.api.gateway.name
    except Exception:
        gname = "?"
    m = hashlib.md5(norm(j.public_key).encode()).hexdigest()
    mark = "  <== ESB的密钥(一致)" if m == hashlib.md5(norm(esb_pub).encode()).hexdigest() else ""
    mark2 = "  <== GSE持有" if m == "0e18be8a0f385db7ba21c81b58fcc265" else ""
    print("   %-14s %s%s%s" % (gname, m, mark, mark2))
PY
' 2>&1 | sed 's/^/  /'
} > /root/sync-names.txt 2>&1
cat /root/sync-names.txt
