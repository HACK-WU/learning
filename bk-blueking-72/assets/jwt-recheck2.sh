#!/usr/bin/env bash
set -uo pipefail
{
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
GSE_MD5="0e18be8a0f385db7ba21c81b58fcc265"

echo "===== 1. GSE 容器持有公钥 md5 ====="
echo "  GSE = $GSE_MD5"

echo ""
echo "===== 2. core_jwt 每条记录的完整公钥 md5（逐条，不 join）====="
kubectl exec "$DP" -n blueking -- sh -c '
python manage.py shell <<PY 2>/dev/null
import hashlib
from django.db import connection
cur = connection.cursor()
cur.execute("SELECT id, api_id, public_key FROM core_jwt")
rows = cur.fetchall()
def norm(pk):
    if pk is None: return ""
    if isinstance(pk, bytes): pk = pk.decode("utf-8","ignore")
    s = str(pk)
    return "".join(l.strip() for l in s.splitlines() if "BEGIN" not in l and "END" not in l)
print("  条数:", len(rows))
seen = {}
for jid, api, pk in rows:
    m = hashlib.md5(norm(pk).encode()).hexdigest()
    seen.setdefault(m, []).append(api)
print("  去重公钥数:", len(seen))
for m, apis in seen.items():
    flag = "  <== 与GSE一致" if m == "0e18be8a0f385db7ba21c81b58fcc265" else ""
    print("   md5=%s  api_ids=%s%s" % (m, apis[:6], flag))
PY
' 2>&1 | sed 's/^/  /' | head -25

echo ""
echo "===== 3. 这些 api 属于哪些 gateway（用 ORM 避免 SQL 字段问题）====="
kubectl exec "$DP" -n blueking -- sh -c '
python manage.py shell <<PY 2>/dev/null
from apigateway.core.models import JWT, API, Gateway
import hashlib
def norm(pk):
    s = str(pk)
    return "".join(l.strip() for l in s.splitlines() if "BEGIN" not in l and "END" not in l)
res = {}
for j in JWT.objects.all():
    m = hashlib.md5(norm(j.public_key).encode()).hexdigest()
    try:
        g = j.api.gateway.name
    except Exception:
        g = "?"
    res.setdefault((g, m), 0)
    res[(g, m)] += 1
for (g, m), c in sorted(res.items()):
    flag = "  <== GSE持有这把" if m == "0e18be8a0f385db7ba21c81b58fcc265" else ""
    print("   gateway=%-12s md5=%s count=%d%s" % (g, m, c, flag))
PY
' 2>&1 | sed 's/^/  /' | head -25
} > /root/jwt-recheck2.txt 2>&1
cat /root/jwt-recheck2.txt
