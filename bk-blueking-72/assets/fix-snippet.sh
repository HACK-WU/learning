#!/usr/bin/env bash
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH
NS=ingress-nginx
CM=ingress-nginx-controller

echo "===== 1. patch 前状态 ====="
kubectl get cm $CM -n $NS -o jsonpath='{.data}' 2>/dev/null | sed 's/^/  data: /'
echo ""

echo ""
echo "===== 2. 执行 patch（放开 snippet）====="
kubectl -n $NS patch cm $CM --type merge \
  -p '{"data":{"allow-snippet-annotations":"true"}}' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. patch 后核验 ====="
kubectl get cm $CM -n $NS -o jsonpath='{.data.allow-snippet-annotations}' 2>/dev/null | sed 's/^/  allow-snippet-annotations: /'
echo ""

echo ""
echo "===== 4. 等 controller 加载新配置（最多 60s）====="
for i in $(seq 1 12); do
  if kubectl logs -n $NS -l app.kubernetes.io/name=ingress-nginx --tail=50 2>/dev/null | grep -q 'allow-snippet-annotations'; then
    echo "  第 ${i}0 秒：controller 已重载配置"
    kubectl logs -n $NS -l app.kubernetes.io/name=ingress-nginx --tail=10 2>/dev/null | grep -iE 'reload|snippet' | sed 's/^/    /'
    break
  fi
  sleep 5
done
echo "  等待结束"

echo ""
echo "===== 5. 实测：能否创建带 snippet 的 ingress（真验证，不看日志猜）====="
kubectl apply -f - <<'EOF' 2>&1 | sed 's/^/  /'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: snippet-probe
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/server-snippet: |
      location ~* "^/metrics" {
        deny all;
        return 403;
      }
spec:
  ingressClassName: nginx
  rules:
  - host: probe.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: snippet-probe
            port:
              number: 80
EOF
