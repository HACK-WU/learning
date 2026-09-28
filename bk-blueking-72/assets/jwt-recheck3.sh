#!/usr/bin/env bash
set -uo pipefail
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
{
echo "===== 抓真实报错 ====="
kubectl exec "$DP" -n blueking -- sh -c '
python manage.py shell <<PY 2>&1 | tail -25
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
print("条数:", len(rows))
seen = {}
for jid, api, pk in rows:
    m = hashlib.md5(norm(pk).encode()).hexdigest()
    seen.setdefault(m, []).append(api)
print("去重公钥数:", len(seen))
for m, apis in seen.items():
    flag = "  <== 与GSE一致" if m == "0e18be8a0f385db7ba21c81b58fcc265" else ""
    print("md5=%s apis=%s%s" % (m, apis[:8], flag))
PY
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== fallback：用 SQL 直接算 md5（不经 python 拼接）====="
kubectl exec "$DP" -n blueking -- sh -c '
python manage.py shell <<PY 2>&1 | tail -20
from django.db import connection
cur=connection.cursor()
cur.execute("""
  SELECT MD5(REPLACE(REPLACE(REPLACE(public_key,\"-----BEGIN PUBLIC KEY-----\",\"\"),\"-----END PUBLIC KEY-----\",\"\"),\"\n\",\"\")) AS m,
         COUNT(*) c, GROUP_CONCAT(api_id)
  FROM core_jwt GROUP BY m
""")
for m,c,apis in cur.fetchall():
    flag="  <== GSE" if m=="0e18be8a0f385db7ba21c81b58fcc265" else ""
    print("md5=%s count=%s apis=%s%s" % (m,c,str(apis)[:60],flag))
PY
' 2>&1 | sed 's/^/  /'
} > /root/jwt-err.txt 2>&1
cat /root/jwt-err.txt
