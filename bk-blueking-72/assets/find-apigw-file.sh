#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. sync-builtin-gateway Job 是否真的同步了密钥 ====="
kubectl logs bk-apigateway-sync-builtin-gateway-1-m2s67 -n blueking --tail=60 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. 它有没有报 gse 相关错误 ====="
kubectl logs bk-apigateway-sync-builtin-gateway-1-m2s67 -n blueking 2>/dev/null | grep -iE 'gse|error|fail|skip' | tail -20 | sed 's/^/  /'

echo ""
echo "===== 3. 当前 core_jwt 公钥（修复前基线）====="
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$DP" -n blueking -- sh -c '
python manage.py shell <<PY 2>/dev/null
import hashlib
from django.db import connection
cur = connection.cursor()
cur.execute("SELECT api_id, public_key FROM core_jwt")
rows=cur.fetchall()
print("  core_jwt 条数:", len(rows))
md=set()
for aid,pk in rows:
    md.add(hashlib.md5(str(pk).encode()).hexdigest())
print("  去重后公钥 md5:", md)
PY
' 2>&1 | sed 's/^/  /' | head -8

echo ""
echo "===== 4. 找 apigateway 的真正 helmfile（在 base 里）====="
grep -ln 'bkapigateway\|apigateway' /root/bk72/install/blueking/base*.yaml.gotmpl /root/bk72/install/blueking/00*.yaml.gotmpl 2>/dev/null | sed 's/^/  /'
echo "  --- base-blueking.yaml.gotmpl 里的 apigateway 段 ---"
grep -n 'apigateway' /root/bk72/install/blueking/base-blueking.yaml.gotmpl 2>/dev/null | head -10 | sed 's/^/    /'

echo ""
echo "===== 5. 该文件依赖的 values（避免再报 domain 错）====="
grep -n 'values' /root/bk72/install/blueking/base-blueking.yaml.gotmpl 2>/dev/null | head -8 | sed 's/^/  /'
} > /root/find-apigw-file.txt 2>&1
cat /root/find-apigw-file.txt
