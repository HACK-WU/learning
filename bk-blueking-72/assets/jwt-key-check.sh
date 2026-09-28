#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. values 里 bkApigatewayPublicKey 的完整定义 ====="
grep -B3 -A6 'bkApigatewayPublicKey' /root/bk72/install/blueking/environments/default/bkgse-ee-values.yaml.gotmpl 2>/dev/null | sed 's/^/  /'
echo "  --- ce 版本 ---"
grep -B3 -A6 'bkApigatewayPublicKey' /root/bk72/install/blueking/environments/default/bkgse-ce-values.yaml.gotmpl 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 2. 该 public key 从哪来（是不是引用 apigateway 生成的）====="
grep -rn 'bkApigatewayPublicKey\|apigatewayPublicKey' /root/bk72/install/blueking/ 2>/dev/null | grep -v 'Binary' | head -12 | sed 's/^/  /'

echo ""
echo "===== 3. 网关当前实际用的公钥（core-api 提供）====="
CP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-core-api' | grep Running | awk '{print $1}' | head -1)
echo "  POD=$CP"
echo "  --- 查 bk-gse gateway 的 public key ---"
kubectl exec "$CP" -n blueking -- sh -c '
  wget -q -O- "http://127.0.0.1/api/v1/open/gateways/bk-gse/public_key/" 2>&1 | head -c 600
  echo ""
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 4. GSE 容器里实际用的公钥（文件/环境变量）====="
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$GP" -n blueking -- sh -c '
  echo "  --- env 全量里搜 key ---"
  env | grep -iE "apigw|public|jwt" | head -10
  echo "  --- 找证书/公钥文件 ---"
  find / -iname "*public*key*" -o -iname "*jwt*" 2>/dev/null | grep -viE "python|site-packages|/proc" | head -10
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 5. GSE 版本与镜像（判断是否版本不匹配）====="
helm list -A 2>/dev/null | grep -E 'bk-gse' | sed 's/^/  /'
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | sed 's/^/  /'
} > /root/jwt-key2.txt 2>&1
cat /root/jwt-key2.txt
