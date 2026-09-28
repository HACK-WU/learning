#!/usr/bin/env bash
set -uo pipefail
{
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)

echo "===== 1. GSE 容器内证书去掉头尾后的 base64 体（md5）====="
GSE_MD5=$(kubectl exec "$GP" -n blueking -- sh -c 'grep -v "BEGIN\|END" /data/gse/cert/apigw_jwt.crt | tr -d "\n" | md5sum | awk "{print \$1}"' 2>/dev/null)
echo "  GSE证书体 md5  = $GSE_MD5"

echo ""
echo "===== 2. apigateway DB 里 bk-gse 的公钥（md5）====="
kubectl exec "$DP" -n blueking -- sh -c '
python manage.py shell <<PY 2>/dev/null
import hashlib
from django.db import connection
cur = connection.cursor()
# 枚举可能存 JWT 公钥的表
cur.execute("SHOW TABLES")
tables = [t[0] for t in cur.fetchall()]
cands = [t for t in tables if "jwt" in t.lower()]
print("  JWT相关表:", cands)
for t in cands:
    cur.execute("SELECT * FROM %s LIMIT 5" % t)
    cols = [d[0] for d in cur.description]
    print("  表", t, "列:", cols)
    for row in cur.fetchall():
        for c, v in zip(cols, row):
            if v and ("PUBLIC" in str(v)[:40].upper() or "BEGIN" in str(v)[:40]):
                print("    ->", c, "md5:", hashlib.md5(str(v).encode()).hexdigest())
PY
' 2>&1 | sed 's/^/  /' | head -25

echo ""
echo "===== 3. 直接查 core_api 表 / gateway 相关（公钥可能存这）====="
kubectl exec "$DP" -n blueking -- sh -c '
python manage.py shell <<PY 2>/dev/null
import hashlib
from django.db import connection
cur = connection.cursor()
cur.execute("SHOW TABLES")
tables = [t[0] for t in cur.fetchall()]
print("  含 gateway 的表:", [t for t in tables if "gateway" in t.lower()][:10])
# 找含 public_key 的列
for t in tables:
    try:
        cur.execute("SHOW COLUMNS FROM %s" % t)
        cols=[r[0] for r in cur.fetchall()]
        for c in cols:
            if "public_key" in c.lower():
                cur.execute("SELECT id, %s FROM %s LIMIT 10" % (c,t))
                for r in cur.fetchall():
                    if r[1]:
                        print("  ", t, c, "id=",r[0], "md5:", hashlib.md5(str(r[1]).encode()).hexdigest())
    except Exception:
        pass
PY
' 2>&1 | sed 's/^/  /' | head -25

echo ""
echo "===== 4. builtinGateway 配置源（GSE 用哪个 publicKeyBase64）====="
grep -rn 'publicKeyBase64' /root/bk72/install/blueking/environments/default/*.yaml 2>/dev/null | head -5 | sed 's/^/  /'
echo "  --- 搜 builtinGateway 定义 ---"
grep -rn 'builtinGateway' /root/bk72/install/blueking/environments/default/*.yaml 2>/dev/null | head -5 | sed 's/^/  /'
} > /root/jwt-db.txt 2>&1
cat /root/jwt-db.txt
