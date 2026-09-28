#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. GSE 侧 JWT 公钥 / 密钥来源 ====="
echo "  --- bkgse values 里 jwt/secret 配置 ---"
grep -iE 'jwt|public_key|private_key|secret' /root/bk72/install/blueking/environments/default/bkgse-ee-values.yaml.gotmpl 2>/dev/null | head -15 | sed 's/^/    /'
grep -iE 'jwt|public_key|private_key|secret' /root/bk72/install/blueking/environments/default/bkgse-ce-values.yaml.gotmpl 2>/dev/null | head -15 | sed 's/^/    /'

echo ""
echo "===== 2. GSE Pod 实际挂载的 jwt 配置 ====="
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
echo "  POD=$GP"
kubectl exec "$GP" -n blueking -- sh -c 'env | grep -iE "jwt|secret|key" | head -15' 2>&1 | sed 's/^/    /'

echo ""
echo "===== 3. GSE data Pod 日志里的 jwt 报错 ====="
kubectl logs "$GP" -n blueking --tail=500 2>/dev/null | grep -iE 'jwt|signature|403' | tail -15 | sed 's/^/  /'

echo ""
echo "===== 4. 平台统一 jwt 公钥（各组件应共用）====="
echo "  --- 搜 secret 资源 ---"
kubectl get secret -n blueking --no-headers 2>/dev/null | grep -iE 'jwt|gse|bkapp|key' | sed 's/^/    /' | head -12

echo ""
echo "===== 5. 对比：GSE 与 ESB 用的公钥是否同源 ====="
echo "  --- gse secret 内容（只看 key 名）---"
for S in $(kubectl get secret -n blueking --no-headers 2>/dev/null | grep -iE 'gse' | awk '{print $1}'); do
  echo "    secret=$S  keys=$(kubectl get secret "$S" -n blueking -o jsonpath='{.data}' 2>/dev/null | tr -d '{}\"' | cut -d: -f1 | tr '\n' ' ')"
done

echo ""
echo "===== 6. monitor 侧配置的 GSE jwt 公钥 ====="
grep -iE 'jwt|public_key|gse' /root/bk72/install/blueking/environments/default/bkmonitor-values.yaml.gotmpl 2>/dev/null | grep -iE 'jwt|key|secret' | head -10 | sed 's/^/  /'
} > /root/jwt-root.txt 2>&1
cat /root/jwt-root.txt
