#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 0. 建一个新的长期探针 Pod ====="
kubectl run netprobe -n $NS --restart=Never --image=hub.bktencent.com/blueking/paas3-apiserver:v1.6.0-beta.32 --command -- sleep 3600 2>&1 | sed 's/^/  /'
for i in $(seq 1 30); do
  S=$(kubectl get pod netprobe -n $NS -o jsonpath='{.status.phase}' 2>/dev/null)
  [ "$S" = "Running" ] && { echo "  Running"; break; }
  sleep 4
done

echo ""
echo "===== 1. 直连 bk-apigateway-bkapi:80 测 sync API ====="
BK=10.96.195.32
kubectl exec netprobe -n $NS -- bash -c "curl -s -o /dev/null -w '    root: HTTP %{http_code}\n' --max-time 8 http://$BK/" 2>&1
kubectl exec netprobe -n $NS -- bash -c "curl -s --max-time 8 http://$BK/api/bk-apigateway/prod/ | head -c 200" 2>&1 | sed 's/^/    /'
echo ""

echo "===== 2. core-api:80 对比 ====="
CA=10.96.60.146
kubectl exec netprobe -n $NS -- bash -c "curl -s -o /dev/null -w '    core-api root: HTTP %{http_code}\n' --max-time 8 http://$CA/" 2>&1
kubectl exec netprobe -n $NS -- bash -c "curl -s --max-time 8 http://$CA/api/v1/apis/ | head -c 200" 2>&1 | sed 's/^/    /'
echo ""

echo "===== 3. 补 ingress：bkapi.paas.example.com -> bk-apigateway-bkapi:80 ====="
cat <<'EOF' | kubectl apply -f - 2>&1 | sed 's/^/  /'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: bk-apigateway-bkapi
  namespace: blueking
spec:
  ingressClassName: nginx
  rules:
  - host: bkapi.paas.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: bk-apigateway-bkapi
            port:
              number: 80
EOF

echo ""
echo "===== 4. 等 ingress 生效后验证 ====="
sleep 12
kubectl exec netprobe -n $NS -- bash -c "curl -s -o /dev/null -w '    bkapi.paas.example.com/ HTTP %{http_code}\n' --max-time 10 http://bkapi.paas.example.com/" 2>&1
kubectl exec netprobe -n $NS -- bash -c "curl -s --max-time 10 http://bkapi.paas.example.com/api/bk-apigateway/prod/ | head -c 200" 2>&1 | sed 's/^/    /'
echo ""

echo "===== 5. 重跑 gse apigw sync ====="
for p in $(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'apigw|synchronization' | grep -v Running | awk '{print $1}'); do
  kubectl delete pod $p -n $NS --wait=false 2>&1 | sed 's/^/  /'
done
# 也删其它可能待重建的
for p in $(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'bk-cmdb-apigw|bk-cmdb-migrate-dataid|bkiam-saas' | grep -v Running | awk '{print $1}'); do
  kubectl delete pod $p -n $NS --wait=false 2>&1 | sed 's/^/  /'
done

echo ""
echo "===== 6. 等 60s 看结果 ====="
sleep 60
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'apigw|synchronization|bkiam-saas' | awk '{printf "  %-50s %-18s 重启%s\n", $1, $3, $4}'
