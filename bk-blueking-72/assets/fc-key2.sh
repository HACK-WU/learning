#!/usr/bin/env bash
set -uo pipefail
EP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-bk-esb-' | grep Running | awk '{print $1}' | head -1)
{
echo "===== 1. 找正确的 settings 模块 ====="
kubectl exec "$EP" -n blueking -c bk-esb -- sh -c '
  echo "  --- 环境变量 ---"
  env | grep -iE "DJANGO|BK_|SETTINGS" | head -8
  echo "  --- settings 文件 ---"
  find /app -maxdepth 3 -name "settings*.py" 2>/dev/null | head -5
  echo "  --- manage.py ---"
  head -20 /app/manage.py 2>/dev/null
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. 直接查 FunctionController 表里的 JWT_KEY（绕过 django setup）====="
kubectl exec "$EP" -n blueking -c bk-esb -- sh -c '
cd /app && python -c "
import os,sys,json,hashlib
sys.path.insert(0,\"/app\")
os.environ[\"DJANGO_SETTINGS_MODULE\"]=\"settings\"
import django
django.setup()
from esb.bkapp.models import FunctionController
rows = FunctionController.objects.filter(func_code__icontains=\"jwt\")
for r in rows:
    print(\"  func_code:\", r.func_code, \" switch:\", r.switch_status)
    try:
        d = json.loads(r.wlist)
        pk = d.get(\"public_key\",\"\")
        pr = d.get(\"private_key\",\"\")
        def norm(p):
            if not p: return \"\"
            return \"\".join(l.strip() for l in str(p).splitlines() if \"BEGIN\" not in l and \"END\" not in l)
        print(\"   ESB签发公钥 md5:\", hashlib.md5(norm(pk).encode()).hexdigest())
        print(\"   private len:\", len(pr))
        print(\"   (GSE持有: 0e18be8a0f385db7ba21c81b58fcc265)\")
    except Exception as e:
        print(\"   parse err:\", e)
" 2>&1 | tail -15
' 2>&1 | sed 's/^/  /'
} > /root/fc-key2.txt 2>&1
cat /root/fc-key2.txt
