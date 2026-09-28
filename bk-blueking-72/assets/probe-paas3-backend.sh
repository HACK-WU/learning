#!/usr/bin/env bash
set -uo pipefail
NS=blueking
echo "===== 后端 API 探活（走 /backend 路径）====="
for p in "/backend/" "/backend/api/v3/" "/healthz" "/ping"; do
  R=$(kubectl run paas3-api-$$ -n $NS --rm -i --restart=Never --image=curlimages/curl:8.5.0 --timeout=45s -- \
    curl -s -o /dev/null -w "%{http_code}" --max-time 12 \
    -H "Host: bkpaas.paas.example.com" "http://ingress-nginx-controller.ingress-nginx.svc.cluster.local$p" 2>/dev/null | tail -1)
  printf "    %-24s -> %s\n" "$p" "${R:-ERR}"
done

echo ""
echo "===== apiserver-web 直连 Pod（带路径）====="
IP=$(kubectl get pod -n $NS --no-headers 2>/dev/null | grep '^bkpaas3-apiserver-web' | awk '{print $1}' | head -1 | xargs -r kubectl get pod -n $NS -o jsonpath='{.status.podIP}' 2>/dev/null)
echo "    podIP=$IP"
if [ -n "$IP" ]; then
  kubectl run paas3-api2-$$ -n $NS --rm -i --restart=Never --image=curlimages/curl:8.5.0 --timeout=45s -- \
    curl -s -o /dev/null -w "    /backend/  HTTP=%{http_code}\n" --max-time 12 "http://$IP:80/backend/" 2>&1 | tail -2
fi

echo ""
echo "===== 登录/鉴权相关：IAM 绕行配置是否仍在 ====="
kubectl get cm bkpaas3-apiserver-general-envs -n $NS -o jsonpath='{.data}' 2>/dev/null | tr ',' '\n' | grep -iE 'IAM_USE_APIGATEWAY|BK_IAM' | sed 's/^/    /'

echo ""
echo "===== apiserver-worker 是否在消费（日志末尾）====="
W=$(kubectl get pod -n $NS --no-headers 2>/dev/null | grep '^bkpaas3-apiserver-worker' | awk '{print $1}' | head -1)
[ -n "$W" ] && kubectl logs "$W" -n $NS --tail=6 2>&1 | grep -viE 'insecure|deprecat|warnings' | sed 's/^/    /'
