#!/usr/bin/env bash
set -uo pipefail
NS=ingress-nginx
CM=ingress-nginx-controller

echo "===== 1. 加上 annotations-risk-level: Critical ====="
kubectl -n $NS patch cm $CM --type merge \
  -p '{"data":{"annotations-risk-level":"Critical"}}' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. 核验 configmap ====="
kubectl get cm $CM -n $NS -o yaml 2>/dev/null | sed -n '/^data:/,/^  metadata/p' | grep -vE '^  metadata' | sed 's/^/  /'

echo ""
echo "===== 3. 等重载（30s）====="
sleep 30
echo "  已等待 30s"

echo ""
echo "===== 4. 实测：再建带 snippet 的 ingress ====="
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

echo ""
echo "===== 5. 结果判定 ====="
if kubectl get ingress snippet-probe -n default >/dev/null 2>&1; then
  echo "  ✅ snippet ingress 创建成功 —— 关卡已解除"
  kubectl delete ingress snippet-probe -n default >/dev/null 2>&1 && echo "  已清理测试 ingress"
else
  echo "  ❌ 仍被拒绝，查看最新错误："
  kubectl logs -n $NS -l app.kubernetes.io/name=ingress-nginx --tail=20 2>/dev/null | grep -iE 'invalid ingress|risky|snippet' | tail -3 | sed 's/^/    /'
fi
