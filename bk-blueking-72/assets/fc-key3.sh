#!/usr/bin/env bash
set -uo pipefail
EP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-bk-esb-' | grep Running | awk '{print $1}' | head -1)
{
echo "===== 决定性比对：ESB 签发公钥 vs GSE 持有公钥 ====="
kubectl exec "$EP" -n blueking -c bk-esb -- sh -c '
cd /app && python 2>&1 <<PY | tail -20
import os, sys, json, hashlib
sys.path.insert(0, "/app")
os.environ["DJANGO_SETTINGS_MODULE"] = "settings"
import django
django.setup()
from esb.utils.func_ctrl import FunctionController, FunctionControllerClient
from esb.utils.jwt_utils import JWTKey

def norm(p):
    if not p: return ""
    if isinstance(p, bytes): p = p.decode("utf-8", "ignore")
    return "".join(l.strip() for l in str(p).splitlines() if "BEGIN" not in l and "END" not in l)

# 方式一：通过 JWTKey 接口
k = JWTKey()
pk = k.get_public_key()
pr = k.get_private_key()
print("  [JWTKey.get_public_key] md5 =", hashlib.md5(norm(pk).encode()).hexdigest())
print("  [JWTKey.get_private_key] len =", len(pr))

# 方式二：直查表
print("")
print("  --- FunctionController 表里 jwt 相关记录 ---")
for r in FunctionController.objects.all():
    if "jwt" in str(r.func_code).lower():
        print("   func_code:", r.func_code, "switch:", r.switch_status, "wlist_len:", len(r.wlist or ""))

print("")
print("  GSE 持有公钥 md5 = 0e18be8a0f385db7ba21c81b58fcc265")
PY
' 2>&1 | sed 's/^/  /'
} > /root/fc-key3.txt 2>&1
cat /root/fc-key3.txt
