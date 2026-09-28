#!/usr/bin/env bash
set -uo pipefail
{
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)

echo "===== 1. 口径统一：GSE 容器公钥（去头尾换行）md5 ====="
GSE_MD5=$(kubectl exec "$GP" -n blueking -- sh -c 'grep -v "BEGIN\|END" /data/gse/cert/apigw_jwt.crt | tr -d "\n" | md5sum | awk "{print \$1}"' 2>/dev/null)
echo "  GSE = $GSE_MD5"

echo ""
echo "===== 2. core_jwt 按 gateway 分组，完整公钥标准化后 md5 ====="
echo "  （上一轮用 LEFT(...,60) 截断导致误判，此处用完整值）"
kubectl exec "$DP" -n blueking -- sh -c '
python manage.py shell <<PY 2>/dev/null
import hashlib
from django.db import connection
cur = connection.cursor()
def norm(pk):
    s=str(pk)
    lines=[l.strip() for l in s.splitlines() if "BEGIN" not in l and "END" not in l]
    return "".join(lines)
cur.execute("""
  SELECT g.name, j.api_id, j.public_key
  FROM core_jwt j
  LEFT JOIN core_api a ON j.api_id=a.id
  LEFT JOIN core_gateway g ON a.gateway_id=g.id
  ORDER BY g.name
""")
rows=cur.fetchall()
print("  总记录数:", len(rows))
from collections import defaultdict
d=defaultdict(set)
for gname,api,pk in rows:
    d[gname or "(null)"].add(hashlib.md5(norm(pk).encode()).hexdigest())
for gname in sorted(d):
    mark=" <== GSE持有" if any(m.startswith("0e18be8a") for m in d[gname]) else ""
    print("  gateway=%-14s 公钥数=%d  md5=%s%s" % (gname, len(d[gname]), list(d[gname])[:2], mark))
PY
' 2>&1 | sed 's/^/  /' | head -25

echo ""
echo "===== 3. 判定：apigw 存的是不是 GSE 那把 ====="
echo "  若上面 gateway=bk-gse 的 md5 含 0e18be8a... -> 密钥一致，403 另有原因"
echo "  若不含 -> 密钥错配成立"
} > /root/jwt-recheck.txt 2>&1
cat /root/jwt-recheck.txt
