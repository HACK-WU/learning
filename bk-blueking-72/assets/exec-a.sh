#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 方案 A 执行：把 bk-gse 的密钥同步成 ESB 的密钥 ====="
echo ""
echo "架构确认（已验证）："
echo "  monitor -> ESB -> GSE(HTTP)   : ESB 用自己密钥签 JWT (with_jwt_header=True, RS512)"
echo "  GSE 用 ConfigMap 里的 apigw_jwt.crt 验签"
echo "  -> 需让 GSE 的证书 = ESB 的公钥"
echo ""

echo "--- 第 1 步：备份当前 values ---"
helm get values bk-gse -n blueking > /root/bk-gse-values.backup.yaml 2>&1
echo "  已备份 /root/bk-gse-values.backup.yaml ($(wc -c < /root/bk-gse-values.backup.yaml) 字节)"

echo ""
echo "--- 第 2 步：取 ESB 公钥 base64 ---"
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
ESB_B64=$(kubectl exec "$DP" -n blueking -- sh -c 'base64 -w0 /tmp/esb_pub.pem' 2>/dev/null | tr -d '\n')
echo "  ESB 公钥 base64 长度: ${#ESB_B64}"
echo "$ESB_B64" > /root/esb_pub.b64
echo "  已存 /root/esb_pub.b64"

echo ""
echo "--- 第 3 步：验证 base64 解码后确实是 ESB 公钥 ---"
echo "$ESB_B64" | base64 -d 2>/dev/null | grep -v 'BEGIN\|END' | tr -d '\n' | md5sum | awk '{print "  解码后 md5 = "$1}'
echo "  (应为 0e82d670218b3380bcbc15d87625a81e)"

echo ""
echo "--- 第 4 步：确认当前值 ---"
helm get values bk-gse -n blueking 2>/dev/null | python3 -c '
import sys,yaml,hashlib,base64
d=yaml.safe_load(sys.stdin) or {}
v=d.get("bkApigatewayPublicKey")
if v:
    raw=base64.b64decode(v)
    norm=b"".join(l.strip() for l in raw.splitlines() if b"BEGIN" not in l and b"END" not in l)
    print("  当前 bkApigatewayPublicKey md5 =",hashlib.md5(norm).hexdigest())
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 准备就绪，等待确认后执行 helm upgrade ====="
} > /root/exec-a.txt 2>&1
cat /root/exec-a.txt
