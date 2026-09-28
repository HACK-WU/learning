#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. 当前 release 的 bkApigatewayPublicKey（base64，前40字符）====="
helm get values bk-gse -n blueking 2>/dev/null | grep -iE 'bkApigatewayPublicKey' | cut -c1-100 | sed 's/^/  /'

echo ""
echo "  --- 解码后指纹，确认它就是 GSE 当前那把 ---"
helm get values bk-gse -n blueking 2>/dev/null | python3 -c '
import sys,yaml,hashlib,base64
d=yaml.safe_load(sys.stdin) or {}
v=d.get("bkApigatewayPublicKey")
if v:
    raw=base64.b64decode(v)
    norm=b"".join(l.strip() for l in raw.splitlines() if b"BEGIN" not in l and b"END" not in l)
    print("  解码后 md5 =",hashlib.md5(norm).hexdigest())
    print("  (GSE当前=0e18be8a0f385db7ba21c81b58fcc265, ESB那把=0e82d670218b3380bcbc15d87625a81e)")
else:
    print("  ! 未取到 bkApigatewayPublicKey")
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. 这个值由谁注入（helmfile gotmpl 里搜）====="
grep -rn 'bkApigatewayPublicKey' /root/bk72/install/blueking/ 2>/dev/null | grep -v '\.bak' | head -10 | sed 's/^/  /'

echo ""
echo "===== 3. 关键：它应该从 apigateway 取 bk-gse 的公钥 ====="
echo "  若注入源是 apigateway DB 里 bk-gse 的公钥 -> 与 GSE 一致(0e18be8a)，但与 ESB(0e82d670)不符"
echo "  修复应改成注入 ESB 的公钥(0e82d670)"

echo ""
echo "===== 4. 生成 ESB 公钥的 base64（供后续 values 使用）====="
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$DP" -n blueking -- sh -c 'base64 -w0 /tmp/esb_pub.pem 2>&1' | head -c 200 | sed 's/^/  /'
echo ""
} > /root/val-a.txt 2>&1
cat /root/val-a.txt
