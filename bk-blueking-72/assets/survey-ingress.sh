#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. 定位 ingress controller ====="
kubectl get pods -A --no-headers 2>/dev/null | grep -iE 'ingress' | sed 's/^/  /'

echo ""
echo "===== 2. controller 启动参数与镜像版本 ====="
kubectl get deploy -A --no-headers 2>/dev/null | grep -iE 'ingress' | while read NS D REST; do
  echo "  --- NS=$NS DEPLOY=$D ---"
  kubectl get deploy "$D" -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | sed 's/^/    镜像: /'
  echo ""
  echo "  args:"
  kubectl get deploy "$D" -n "$NS" -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>/dev/null | sed 's/^/    /'
done

echo ""
echo "===== 3. ingress-nginx ConfigMap ====="
kubectl get cm -A --no-headers 2>/dev/null | grep -iE 'ingress' | while read NS C REST; do
  echo "  --- NS=$NS CM=$C ---"
  kubectl get cm "$C" -n "$NS" -o jsonpath='{.data}' 2>/dev/null | tr ',' '\n' | sed 's/^/    /'
done

echo ""
echo "===== 4. admission webhook（谁在拦截）====="
kubectl get validatingwebhookconfigurations --no-headers 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 5. blueking ingress 的 nginx 注解（标出 snippet）====="
kubectl get ingress -n blueking -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for it in d.get('items',[]):
    ann=it['metadata'].get('annotations',{}) or {}
    ng={k:v for k,v in ann.items() if 'nginx' in k.lower()}
    if ng:
        print('  ingress:',it['metadata']['name'])
        for k,v in ng.items():
            mark=' <== SNIPPET' if 'snippet' in k.lower() else ''
            print('     ',k,'=',str(v)[:70],mark)
" 2>/dev/null

echo ""
echo "===== 6. bk-apigateway release 失败详情（确认被拒资源）====="
helm history bk-apigateway -n blueking --max 3 2>/dev/null | sed 's/^/  /'
} > /root/survey-ingress.txt 2>&1
cat /root/survey-ingress.txt
