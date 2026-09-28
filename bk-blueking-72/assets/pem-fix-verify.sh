#!/usr/bin/env bash
set -uo pipefail
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
{
echo "===== 规范化 PEM 后验证 bk-gse 密钥对 ====="
kubectl exec "$DP" -n blueking -- sh -c '
python manage.py shell <<PY 2>&1 | tail -30
import jwt, datetime, re, hashlib
from django.db import connection

def fix_pem(s, kind):
    if s is None: return None
    if isinstance(s, bytes): s = s.decode("utf-8","ignore")
    s = str(s).strip()
    if "BEGIN" in s:
        return s
    # 没有 PEM 头，补上（每 64 字符换行）
    body = re.sub(r"\s+", "", s)
    lines = [body[i:i+64] for i in range(0, len(body), 64)]
    return "-----BEGIN %s-----\n%s\n-----END %s-----\n" % (kind, "\n".join(lines), kind)

cur=connection.cursor()
cur.execute("SELECT api_id, private_key, public_key FROM core_jwt WHERE api_id=9")
api_id, priv, pub = cur.fetchone()

priv_pem = fix_pem(priv, "PRIVATE KEY")
pub_pem  = fix_pem(pub,  "PUBLIC KEY")
print("  规范化后 private 长度:", len(priv_pem))
print("  规范化后 public  长度:", len(pub_pem))
print("  public md5:", hashlib.md5("".join(l.strip() for l in pub_pem.splitlines() if "BEGIN" not in l and "END" not in l).encode()).hexdigest())
print("  (对比 GSE 持有: 0e18be8a0f385db7ba21c81b58fcc265)")

# 自签自验
try:
    tok = jwt.encode({"iss":"bk-gse","exp":datetime.datetime.utcnow()+datetime.timedelta(minutes=5)},
                     priv_pem, algorithm="RS256")
    print("  ✅ bk-gse 私钥签名成功")
    try:
        jwt.decode(tok, pub_pem, algorithms=["RS256"])
        print("  ✅ bk-gse 公钥验证通过 -> 密钥对健康")
    except Exception as e:
        print("  ❌ 公钥验证失败:", type(e).__name__, e)
except Exception as e:
    print("  ❌ 私钥签名失败:", type(e).__name__, str(e)[:200])
PY
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 结论 ====="
echo "  若密钥对健康 -> invalid signature 的原因是签发方不是 bk-gse"
echo "  （ESB 日志 req_app_code=bk_monitorv3，而 bk_monitorv3 不在 gateway 列表）"
} > /root/pem-fix.txt 2>&1
cat /root/pem-fix.txt
