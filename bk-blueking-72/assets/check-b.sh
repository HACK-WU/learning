#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 核验：apigateway 是否也直接转发到 GSE HTTP ====="
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$DP" -n blueking -- sh -c '
cd /app && python 2>&1 <<PY | tail -30
import os,sys
sys.path.insert(0,"/app")
os.environ["DJANGO_SETTINGS_MODULE"]="apigateway.conf.default"
import django
django.setup()
from apigateway.core.models import Gateway, Stage, Backend, Resource
from apigateway.core.models import BackendConfig
g=Gateway.objects.get(name="bk-gse")
print("  bk-gse gateway id:",g.id)
print("")
print("  --- 有 Backend 吗（有则说明 apigateway 会转发到 GSE）---")
bs=list(Backend.objects.filter(gateway=g))
print("  Backend 数量:",len(bs))
for b in bs[:5]:
    print("   backend:",b.name)
    for bc in BackendConfig.objects.filter(backend=b):
        cfg=bc.config or {}
        hosts=cfg.get("hosts",[])
        for h in (hosts if isinstance(hosts,list) else []):
            print("      host:",h.get("host"),"port:",h.get("port"))
print("")
print("  --- Resource 数量 ---")
print("  resources:",Resource.objects.filter(gateway=g).count())
PY
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 核验：还有谁用 bk-gse 的公钥（改了会影响谁）====="
kubectl exec "$DP" -n blueking -- sh -c '
cd /app && python 2>&1 <<PY | tail -20
import os,sys,hashlib
sys.path.insert(0,"/app")
os.environ["DJANGO_SETTINGS_MODULE"]="apigateway.conf.default"
import django
django.setup()
from apigateway.core.models import Gateway
g=Gateway.objects.get(name="bk-gse")
def norm(p):
    if not p: return ""
    if isinstance(p,bytes): p=p.decode("utf-8","ignore")
    return "".join(l.strip() for l in str(p).splitlines() if "BEGIN" not in l and "END" not in l)
from apigateway.core.models import JWT
for j in JWT.objects.filter(gateway=g):
    print("  bk-gse JWT 公钥 md5 =",hashlib.md5(norm(j.public_key).encode()).hexdigest())
PY
' 2>&1 | sed 's/^/  /'
} > /root/check-b.txt 2>&1
cat /root/check-b.txt
