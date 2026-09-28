#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. bk-apigateway 的 bkapi ingress 用哪个 class（决定成败）====="
kubectl get ingress bk-apigateway-bkapi -n blueking -o yaml 2>/dev/null | grep -iE 'ingressClassName|configuration-snippet|proxy-read-timeout|X-Request-Uri' | sed 's/^/  /'

echo ""
echo "===== 2. 关键探测：用 class=bk-ingress-nginx 带 snippet 会不会被拒 ====="
cat <<'EOF' | kubectl apply -f - 2>&1 | sed 's/^/  /'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: snippet-probe-bk
  namespace: blueking
  annotations:
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_set_header X-Request-Uri $request_uri;
spec:
  ingressClassName: bk-ingress-nginx
  rules:
  - host: snippet-probe-bk.local
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
echo "  结果: $(kubectl get ingress snippet-probe-bk -n blueking --no-headers 2>/dev/null || echo '创建失败/不存在')"
kubectl delete ingress snippet-probe-bk -n blueking --ignore-not-found --wait=false 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. helmfile 里 bk-apigateway 的 ingress 段配置 ====="
grep -n -A20 '^ingress:' /root/bk72/install/blueking/environments/default/bkapigateway-values.yaml.gotmpl 2>/dev/null | head -30 | sed 's/^/  /'

echo ""
echo "===== 4. 现有 bk-apigateway-bkapi 是 24h 前创建的（3h41m 那行是重建？）====="
echo "  --- ingress 创建时间 ---"
kubectl get ingress bk-apigateway-bkapi -n blueking -o jsonpath='  creationTimestamp={.metadata.creationTimestamp}{"\n"}  resourceVersion={.metadata.resourceVersion}{"\n"}' 2>/dev/null

echo ""
echo "===== 5. bk-apigateway 当前 release 与 revision ====="
helm list -A 2>/dev/null | grep -E 'bk-apigateway' | sed 's/^/  /'
helm get values bk-apigateway -n blueking -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for k in ['ingress','gateway','bkapi','apigw']:
    if k in d:
        print('  %s = %s' % (k, json.dumps(d[k],ensure_ascii=False)[:300]))
" 2>/dev/null

echo ""
echo "===== 6. 判定重跑可行性 ====="
echo "  chart 需要: annotations.configuration-snippet = proxy_set_header X-Request-Uri"
echo "  已存在 ingress bk-apigateway-bkapi class=nginx 已带该注解? 见第1段"
} > /root/decide-class.txt 2>&1
cat /root/decide-class.txt
