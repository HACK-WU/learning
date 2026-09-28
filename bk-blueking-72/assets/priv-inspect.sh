#!/usr/bin/env bash
set -uo pipefail
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
{
echo "===== 1. 库里 private_key 到底存了什么 ====="
kubectl exec "$DP" -n blueking -- sh -c '
python manage.py shell <<PY 2>&1 | tail -20
from django.db import connection
cur=connection.cursor()
cur.execute("SELECT api_id, private_key, public_key FROM core_jwt WHERE api_id=9")
r=cur.fetchone()
priv=r[1]; pub=r[2]
if isinstance(priv,bytes): priv=priv.decode("utf-8","ignore")
if isinstance(pub,bytes): pub=pub.decode("utf-8","ignore")
print("  private_key repr(前120):")
print("   ", repr(priv)[:120])
print("  private_key 长度:", len(priv))
print("  public_key  长度:", len(pub))
print("")
print("  --- 其他 gateway 的 private_key 长度（对照）---")
cur.execute("SELECT api_id, LENGTH(private_key), LENGTH(public_key) FROM core_jwt ORDER BY api_id")
for api,lp,lu in cur.fetchall():
    mark="  <== bk-gse(异常)" if api==9 else ""
    print("   api=%-3s priv_len=%-6s pub_len=%-6s%s" % (api,lp,lu,mark))
PY
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. 结论判定 ====="
echo "  若只有 api=9 的 priv 长度异常 -> bk-gse 私钥损坏，需重新 update_jwt_key"
echo "  若全部异常 -> 是取值方式问题，需换读取方式"
} > /root/priv-inspect.txt 2>&1
cat /root/priv-inspect.txt
