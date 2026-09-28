#!/usr/bin/env bash
set -uo pipefail
NS=blueking
echo "===== 1. 实际返回内容（判断是不是应用真页）====="
kubectl run paas3-body-$$ -n $NS --rm -i --restart=Never --image=curlimages/curl:8.5.0 --timeout=60s -- \
  curl -s --max-time 20 -H "Host: bkpaas.paas.example.com" \
  http://ingress-nginx-controller.ingress-nginx.svc.cluster.local/ 2>&1 | head -30 | sed 's/^/    /'

echo ""
echo "===== 2. 每个 paas3 ingress 的 host 与后端（看是否重复指向同一服务）====="
for ing in bkpaas3-apiserver-web bkpaas3-svc-bkrepo-web bkpaas3-svc-mysql-web bkpaas3-svc-otel-web bkpaas3-svc-rabbitmq-web bkpaas3-webfe-web; do
  H=$(kubectl get ingress $ing -n $NS -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)
  P=$(kubectl get ingress $ing -n $NS -o jsonpath='{.spec.rules[0].http.paths[0].path}' 2>/dev/null)
  B=$(kubectl get ingress $ing -n $NS -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}' 2>/dev/null)
  printf "    %-30s host=%-32s path=%-14s -> %s\n" "$ing" "$H" "$P" "$B"
done

echo ""
echo "===== 3. 直接打 Pod IP（绕过 ingress，验证应用本身）====="
for d in bkpaas3-webfe-web bkpaas3-apiserver-web; do
  IP=$(kubectl get pod -n $NS -l app=$d -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)
  if [ -z "$IP" ]; then IP=$(kubectl get pod -n $NS --no-headers | grep "^$d" | awk '{print $1}' | head -1 | xargs -r kubectl get pod -n $NS -o jsonpath='{.status.podIP}' 2>/dev/null); fi
  echo "  --- $d podIP=${IP:-无} ---"
  if [ -n "$IP" ]; then
    kubectl run paas3-ip-$$ -n $NS --rm -i --restart=Never --image=curlimages/curl:8.5.0 --timeout=60s -- \
      curl -s -o /dev/null -w "    HTTP=%{http_code} 大小=%{size_download}\n" --max-time 15 "http://$IP/" 2>&1 | tail -2
  fi
done
