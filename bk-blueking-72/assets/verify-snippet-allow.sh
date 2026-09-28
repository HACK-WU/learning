#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. ConfigMap 修改时间 vs 失败时间（关键）====="
echo "  bk-apigateway 失败于: Tue Sep 22 17:55:58 2026"
echo ""
echo "  --- ingress-nginx-controller CM 的 metadata ---"
kubectl get cm ingress-nginx-controller -n ingress-nginx -o jsonpath='  creationTimestamp={.metadata.creationTimestamp}{"\n"}{"  annotations="}{.metadata.annotations}{"\n"}' 2>/dev/null
echo "  --- 该 CM 的 yaml 头部（看 managedFields / 最近更新）---"
kubectl get cm ingress-nginx-controller -n ingress-nginx -o yaml 2>/dev/null | head -20 | sed 's/^/    /'

echo ""
echo "===== 2. 哪个 ingress 用了 configuration-snippet（从 chart 找）====="
rm -rf /tmp/apigwchart && mkdir -p /tmp/apigwchart
helm pull blueking/bk-apigateway --version 1.13.28 --destination /tmp/apigwchart --untar 2>&1 | head -2
echo "  --- chart 里搜 configuration-snippet ---"
grep -rn 'configuration-snippet' /tmp/apigwchart/ 2>/dev/null | head -8 | sed 's/^/    /'

echo ""
echo "===== 3. bk-apigateway 现有 ingress 与 class ====="
kubectl get ingress -n blueking --no-headers 2>/dev/null | grep -iE 'apigw|apigateway' | sed 's/^/  /'
echo "  --- 上面这些 ingress 的 class ---"
kubectl get ingress -n blueking -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for it in d.get('items',[]):
    n=it['metadata']['name']
    if 'apigw' in n or 'apigateway' in n:
        spec=it.get('spec',{})
        print('  ',n,'class=',spec.get('ingressClassName'),'annotations=',list((it['metadata'].get('annotations') or {}).keys()))
" 2>/dev/null

echo ""
echo "===== 4. helmfile 里 apigateway 的 ingress 配置 ====="
grep -rn 'configuration-snippet\|ingressClass\|snippet' /root/bk72/install/blueking/environments/default/bkapigateway-values.yaml.gotmpl 2>/dev/null | head -12 | sed 's/^/  /'

echo ""
echo "===== 5. 验证：现在创建一个带 configuration-snippet 的 ingress 会不会被拒 ====="
cat <<'EOF' | kubectl apply -f - 2>&1 | sed 's/^/  /'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: snippet-probe
  namespace: blueking
  annotations:
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "X-Probe: 1";
spec:
  ingressClassName: bk-ingress-nginx
  rules:
  - host: snippet-probe.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: bk-ingress-nginx
            port:
              number: 80
EOF

echo ""
echo "===== 6. 探测结果判定 ====="
kubectl get ingress snippet-probe -n blueking --no-headers 2>/dev/null | sed 's/^/  /' || echo "  (创建失败 -> 仍被拦截)"
kubectl delete ingress snippet-probe -n blueking --ignore-not-found --wait=false 2>&1 | sed 's/^/  /'
} > /root/verify-allow.txt 2>&1
cat /root/verify-allow.txt
