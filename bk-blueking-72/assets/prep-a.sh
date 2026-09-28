#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. GSE 证书挂载源（决定改哪才能生效）====="
kubectl get pod -n blueking $(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1) -o jsonpath='{range .spec.volumes[*]}{.name}{"="}{.secret.secretName}{.configMap.name}{"\n"}{end}' 2>&1 | sed 's/^/  /'

echo ""
echo "  --- 找挂载到 /data/gse/cert 的卷 ---"
kubectl get pod -n blueking $(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1) -o json 2>/dev/null | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    for c in d["spec"]["containers"]:
        if c["name"]!="bk-gse-data": continue
        for m in c.get("volumeMounts",[]):
            if "cert" in m["mountPath"]:
                print("   container:",c["name"],"mountPath:",m["mountPath"],"volume:",m["name"])
    for v in d["spec"]["volumes"]:
        print("   volume:",v["name"],"->",v.get("secret",{}).get("secretName") or v.get("configMap",{}).get("name") or v.get("hostPath",{}).get("path"))
except Exception as e:
    print("   parse err:",e)
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. 备份：ESB 当前密钥指纹 + bk-gse gateway 当前密钥 ====="
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$DP" -n blueking -- sh -c '
cd /app && python 2>&1 <<PY | tail -20
import os,sys,hashlib,json
sys.path.insert(0,"/app")
os.environ["DJANGO_SETTINGS_MODULE"]="apigateway.conf.default"
import django
django.setup()
from apigateway.apps.esb.bkcore.models import FunctionController
from apigateway.core.models import Gateway, JWT
def norm(p):
    if not p: return ""
    if isinstance(p,bytes): p=p.decode("utf-8","ignore")
    return "".join(l.strip() for l in str(p).splitlines() if "BEGIN" not in l and "END" not in l)
k=FunctionController.objects.get_jwt_key() or {}
print("  ESB公钥 md5 =",hashlib.md5(norm(k.get("public_key","")).encode()).hexdigest())
print("  ESB私钥 len =",len(k.get("private_key","")))
for j in JWT.objects.all():
    try:
        g=j.gateway
        if g and g.name=="bk-gse":
            print("  bk-gse gateway 公钥 md5 =",hashlib.md5(norm(j.public_key).encode()).hexdigest())
    except Exception as e:
        pass
PY
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. 备份 ESB 公钥到本地（供写入 GSE 证书）====="
kubectl exec "$DP" -n blueking -- sh -c '
cd /app && python 2>&1 <<PY
import os,sys
sys.path.insert(0,"/app")
os.environ["DJANGO_SETTINGS_MODULE"]="apigateway.conf.default"
import django
django.setup()
from apigateway.apps.esb.bkcore.models import FunctionController
k=FunctionController.objects.get_jwt_key() or {}
pub=k.get("public_key","")
if isinstance(pub,bytes): pub=pub.decode("utf-8")
open("/tmp/esb_pub.pem","w").write(pub)
print("  written /tmp/esb_pub.pem len=",len(pub))
PY
' 2>&1 | sed 's/^/  /'
} > /root/prep-a.txt 2>&1
cat /root/prep-a.txt
