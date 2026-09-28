#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. 两个 failed release 的失败详情 ====="
helm history bk-apigateway -n blueking --max 3 2>/dev/null | sed 's/^/  /'
echo ""
helm history bk-gse -n blueking --max 3 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 2. 关键判定：网关里 bk-gse 的 API 是否用了预置密钥对 ====="
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$DP" -n blueking -- sh -c '
python manage.py shell <<PY 2>/dev/null
import hashlib
from django.db import connection
cur = connection.cursor()
print("  --- core_jwt 每条记录的 api_id 与 public_key md5 ---")
cur.execute("SELECT api_id, LEFT(public_key,60) FROM core_jwt")
for aid, pk in cur.fetchall():
    print("   api_id=%s  pk_md5=%s" % (aid, hashlib.md5(str(pk).encode()).hexdigest()))
print("")
print("  --- 这些 api 属于哪个 gateway ---")
cur.execute("""
    SELECT j.api_id, a.gateway_id, g.name
    FROM core_jwt j
    LEFT JOIN core_api a ON j.api_id = a.id
    LEFT JOIN core_gateway g ON a.gateway_id = g.id
""")
for r in cur.fetchall():
    print("   api_id=%s gateway_id=%s gateway=%s" % r)
PY
' 2>&1 | sed 's/^/  /' | head -20

echo ""
echo "===== 3. GSE 的 apigwSync 是否成功（决定密钥对是否注册）====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'gse.*sync|apigwsync' | sed 's/^/  /' || echo "  (无独立 sync Pod)"
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-admin-' | grep Running | awk '{print $1}' | head -1)
echo "  --- gse-admin 日志里的 sync 结果 ---"
kubectl logs "$GP" -n blueking --tail=300 2>/dev/null | grep -iE 'sync|apigw|fail|error' | tail -12 | sed 's/^/    /'

echo ""
echo "===== 4. 结论性判定 ====="
echo "  若 core_jwt 中存在 gateway=bk-gse 的记录，且其 public_key != 0e18be8a..."
echo "  --> 证实：网关签发用的密钥对 != GSE 校验用的公钥，即密钥错配（根因坐实）"
} > /root/rootcause.txt 2>&1
cat /root/rootcause.txt
