#!/usr/bin/env bash
set -uo pipefail
{
EP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-bk-esb-' | grep Running | awk '{print $1}' | head -1)
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)

echo "===== 1. GSE 证书的 PEM 格式（PKCS#1 vs PKCS#8 决定解析成败）====="
kubectl exec "$GP" -n blueking -c bk-gse-data -- sh -c '
  echo "  --- 证书第一行（决定格式）---"
  head -1 /data/gse/cert/apigw_jwt.crt
  echo "  --- 证书字节数 ---"
  wc -c /data/gse/cert/apigw_jwt.crt
  echo "  --- 有无 BEGIN 标记 ---"
  grep -c "BEGIN" /data/gse/cert/apigw_jwt.crt
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. ESB 源码里 JWT 签发逻辑（决定性）====="
kubectl exec "$EP" -n blueking -- sh -c '
  echo "  --- 找 signing / jwt 相关源码 ---"
  find /app -name "*.py" 2>/dev/null | xargs grep -ln "def.*jwt\|jwt.encode\|sign_jwt" 2>/dev/null | head -8
  echo ""
  echo "  --- esb 组件目录结构 ---"
  ls /app 2>/dev/null | head -15
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. 关键：ESB 转发时签 JWT 用哪个密钥 ====="
kubectl exec "$EP" -n blueking -- sh -c '
  for f in $(find /app -name "*.py" 2>/dev/null | xargs grep -ln "jwt.encode\|_sign_jwt\|generate_jwt" 2>/dev/null | head -5); do
    echo "  ==== 文件: $f ===="
    grep -n -B5 -A20 "jwt.encode\|_sign_jwt\|generate_jwt" "$f" 2>/dev/null | head -45
  done
' 2>&1 | sed 's/^/  /' | head -80

echo ""
echo "===== 4. apigateway 数据库里所有含密钥的表 ====="
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$DP" -n blueking -- sh -c '
python manage.py shell <<PY 2>&1 | tail -25
from django.db import connection
cur = connection.cursor()
cur.execute("SHOW TABLES")
tables = [t[0] for t in cur.fetchall()]
print("  含 key/secret/jwt 的表:")
for t in tables:
    tl = t.lower()
    if any(k in tl for k in ["jwt","key","secret","crypto","sign"]):
        print("    ", t)
PY
' 2>&1 | sed 's/^/  /' | head -20
} > /root/esb-signer.txt 2>&1
cat /root/esb-signer.txt
