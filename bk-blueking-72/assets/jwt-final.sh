#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 精确比对：GSE 容器内证书 vs 配置文件里 bk-gse 的公钥 ====="
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)

echo "  --- 1. GSE 容器内证书（去头尾、压成一行）---"
GSE_BODY=$(kubectl exec "$GP" -n blueking -- sh -c 'grep -v "BEGIN\|END" /data/gse/cert/apigw_jwt.crt | tr -d "\n"' 2>/dev/null)
echo "  GSE  : $(echo -n "$GSE_BODY" | md5sum | awk '{print $1}')  len=$(echo -n "$GSE_BODY" | wc -c)"

echo ""
echo "  --- 2. 配置文件里每个 builtinGateway 的公钥（解码后比对）---"
python3 - <<PY
import re,base64,hashlib
p="/root/bk72/install/blueking/environments/default/bkapigateway_builtin_keypair.yaml"
txt=open(p,encoding="utf-8").read()
blocks=re.findall(r'(\S+):\s*\n\s*publicKeyBase64:\s*(\S+)', txt)
for name,b64 in blocks:
    try:
        dec=base64.b64decode(b64).decode()
        body="".join(l for l in dec.splitlines() if "BEGIN" not in l and "END" not in l)
        print("  %-20s md5=%s len=%d" % (name, hashlib.md5(body.encode()).hexdigest(), len(body)))
    except Exception as e:
        print("  %-20s err=%s" % (name,e))
PY

echo ""
echo "  --- 3. 结论判定 ---"
echo "  GSE 容器内: $GSE_BODY" | head -c 200
echo ""
} > /root/jwt-final.txt 2>&1
cat /root/jwt-final.txt
