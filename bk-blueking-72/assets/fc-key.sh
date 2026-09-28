#!/usr/bin/env bash
set -uo pipefail
EP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-bk-esb-' | grep Running | awk '{print $1}' | head -1)
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
{
echo "===== 1. FunctionControllerClient.get_jwt_key() 实现 ====="
kubectl exec "$EP" -n blueking -c bk-esb -- cat /app/esb/utils/func_ctrl.py 2>&1 | grep -n -A30 "def get_jwt_key" | head -45 | sed 's/^/  /'

echo ""
echo "===== 2. 实际调 get_jwt_key 拿到什么（决定性）====="
kubectl exec "$EP" -n blueking -c bk-esb -- sh -c '
cd /app && python -c "
import django, os, hashlib
os.environ.setdefault(\"DJANGO_SETTINGS_MODULE\",\"esb.settings\")
django.setup()
from esb.utils.jwt_utils import JWTKey
pk = JWTKey().get_public_key()
pr = JWTKey().get_private_key()
def norm(p):
    if p is None: return \"\"
    if isinstance(p, bytes): p = p.decode(\"utf-8\",\"ignore\")
    return \"\".join(l.strip() for l in str(p).splitlines() if \"BEGIN\" not in l and \"END\" not in l)
print(\"  ESB 签发用 public  md5:\", hashlib.md5(norm(pk).encode()).hexdigest())
print(\"  ESB 签发用 private len:\", len(pr))
print(\"  public 前40字符:\", norm(pk)[:40])
print(\"  (GSE 持有: 0e18be8a0f385db7ba21c81b58fcc265)\")
" 2>&1 | tail -10
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. GSE 持有公钥的完整 md5（复核，不截断）====="
kubectl exec "$GP" -n blueking -c bk-gse-data -- sh -c '
  grep -v "BEGIN\|END" /data/gse/cert/apigw_jwt.crt | tr -d "\n" | md5sum | awk "{print \$1}"
' 2>&1 | sed 's/^/  GSE公钥md5: /'

echo ""
echo "===== 4. 算法确认：ESB 用 RS512，GSE 是否接受 ====="
echo "  ESB 源码: ALGORITHM = \"RS512\""
echo "  需确认 GSE 配置的 algorithm"
kubectl exec "$GP" -n blueking -c bk-gse-data -- sh -c '
  echo "  --- GSE 配置里搜 alg/RS512/RS256 ---"
  grep -rsiE "algorithm|RS512|RS256|alg" /data/gse/etc/ 2>/dev/null | head -8
' 2>&1 | sed 's/^/  /'
} > /root/fc-key.txt 2>&1
cat /root/fc-key.txt
