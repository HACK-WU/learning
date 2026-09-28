#!/usr/bin/env bash
set -uo pipefail
{
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)

echo "===== 1. 确认：ESB 用哪个 app 的密钥签 JWT ====="
echo "  ESB 日志: req_app_code=bk_monitorv3 -> ESB 以 bk_monitorv3 身份签发"
echo "  GSE 验签用的是 bk-gse 的公钥 (apigw_jwt.crt)"
echo "  --> 若签发方 != bk-gse，签名必然不匹配"

echo ""
echo "===== 2. 查 ESB 的 jwt 签发配置 ====="
kubectl exec -n blueking "$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-bk-esb-' | grep Running | awk '{print $1}' | head -1)" -- sh -c '
  echo "  --- esb 配置里的 jwt ---"
  find /app -maxdepth 2 -iname "*.yaml" -o -maxdepth 2 -iname "*.py" 2>/dev/null | head -5
  grep -rsiE "jwt_|signature_app|use_app_code" /app/esb/configs/*.yaml 2>/dev/null | head -10
  echo "  --- 环境变量里的 app ---"
  env | grep -iE "^BK_APP|APP_CODE" | head -6
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. 关键验证：用 bk-gse 公钥验 bk_monitorv3 签的 token ====="
kubectl exec "$DP" -n blueking -- sh -c '
python manage.py shell <<PY 2>&1 | tail -20
import jwt, datetime
from apigateway.core.models import Gateway
gse = Gateway.objects.filter(name="bk-gse").first()
# 取网关存的私钥（签发用）
from django.db import connection
cur=connection.cursor()
cur.execute("SELECT api_id, private_key, public_key FROM core_jwt WHERE api_id=9")
row=cur.fetchone()
priv = row[1]
pub  = row[2]
if isinstance(priv, bytes): priv=priv.decode()
if isinstance(pub, bytes): pub=pub.decode()
print("  取到 bk-gse 私钥长度:", len(priv))
# 用 bk-gse 私钥签一个
tok = jwt.encode({"iss":"bk-gse","exp":datetime.datetime.utcnow()+datetime.timedelta(minutes=5)}, priv, algorithm="RS256")
print("  用 bk-gse 私钥签名成功, token 前50:", tok[:50])
# 用 bk-gse 公钥验
try:
    d = jwt.decode(tok, pub, algorithms=["RS256"])
    print("  ✅ 用 bk-gse 公钥验证: 通过 -> 密钥对本身没问题")
except Exception as e:
    print("  ❌ 用 bk-gse 公钥验证失败:", e)
PY
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 4. 结论判定 ====="
echo "  若第3步通过 -> 密钥对健康，403 是因为 ESB 用了别的 app(bk_monitorv3) 的密钥签发"
echo "  --> 根因：ESB 转发到 GSE 时，JWT 签发方身份不对"
} > /root/verify-signer.txt 2>&1
cat /root/verify-signer.txt
