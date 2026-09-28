#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. helm release bk-gse 的 values 里 apigw_jwt 来源 ====="
helm get values bk-gse -n blueking 2>/dev/null | grep -iE 'apigw|jwt|cert' | head -10 | sed 's/^/  /'
echo "  (若为空，说明是 chart 模板内生成或从别处注入)"

echo ""
echo "===== 2. 本地 helmfile/chart 里 bk-gse-certs 模板 ====="
find /root/bk72 -path '*gse*' -name '*.yaml' 2>/dev/null | head -8 | sed 's/^/  /'
echo "  --- 搜模板里 apigw_jwt ---"
grep -rn 'apigw_jwt' /root/bk72 2>/dev/null | head -8 | sed 's/^/  /'

echo ""
echo "===== 3. 关键决策：改 ConfigMap 会不会被 helm 覆盖回去 ====="
echo "  ConfigMap 带 labels: app.kubernetes.io/managed-by=Helm"
echo "  -> 下次 helm upgrade 会回滚我们的修改"
echo "  -> 若要从根上修，应改生成它的源头（values 或生成脚本）"

echo ""
echo "===== 4. 找生成 apigw_jwt.crt 的脚本（它可能从 apigateway 拿公钥）====="
grep -rln 'apigw_jwt\|update_jwt_key' /root/bk72/ 2>/dev/null | head -8 | sed 's/^/  /'

echo ""
echo "===== 5. 确认 ESB 公钥内容（待写入）====="
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$DP" -n blueking -- sh -c 'head -3 /tmp/esb_pub.pem 2>&1; echo "..."; wc -c /tmp/esb_pub.pem' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 6. 改前完整备份 ConfigMap ====="
kubectl get cm bk-gse-certs -n blueking -o yaml > /root/bk-gse-certs.backup.yaml 2>&1
echo "  已备份到 /root/bk-gse-certs.backup.yaml  ($(wc -c < /root/bk-gse-certs.backup.yaml) 字节)"
} > /root/cm-b.txt 2>&1
cat /root/cm-b.txt
