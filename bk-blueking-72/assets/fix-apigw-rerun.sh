#!/usr/bin/env bash
set -uo pipefail
BK=/root/bk72/install/blueking
cd "$BK" || exit 1
export HELMFILE=/root/bk72/install/bin/helmfile

{
echo "===== 0. 修复前快照（可回滚比对）====="
kubectl get ingress bk-apigateway-bkapi -n blueking -o jsonpath='  annotations={.metadata.annotations}{"\n"}' 2>/dev/null
helm list -A 2>/dev/null | grep -E 'bk-apigateway' | sed 's/^/  /'

echo ""
echo "===== 1. 找到 apigateway 对应的 helmfile 文件 ====="
ls /root/bk72/install/blueking/*.yaml.gotmpl 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 2. 重跑 helmfile sync（apigateway）====="
echo "  开始: $(date '+%F %T')"
F=$(grep -rln 'bkapigateway\|apigateway' /root/bk72/install/blueking/*.yaml.gotmpl 2>/dev/null | head -1)
echo "  使用文件: $F"
if [ -n "$F" ]; then
  timeout 2400 $HELMFILE -f "$(basename $F)" sync 2>&1 | tail -50
else
  echo "  (未找到 apigateway helmfile，改用 helm upgrade 直接重试)"
  timeout 1800 helm upgrade --install bk-apigateway blueking/bk-apigateway \
    --version 1.13.28 -n blueking \
    -f environments/default/bkapigateway-values.yaml.gotmpl \
    --timeout 30m 2>&1 | tail -40
fi
echo "  结束: $(date '+%F %T')"

echo ""
echo "===== 3. 修复后状态 ====="
helm list -A 2>/dev/null | grep -E 'bk-apigateway' | sed 's/^/  /'
echo "  --- bkapi ingress 注解（应有 configuration-snippet）---"
kubectl get ingress bk-apigateway-bkapi -n blueking -o jsonpath='{.metadata.annotations}' 2>/dev/null | tr ',' '\n' | sed 's/^/    /'

echo ""
echo "===== 4. apigateway Pod 是否重建 ====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'apigateway' | sed 's/^/  /'
} > /root/fix-apigw.txt 2>&1
cat /root/fix-apigw.txt
