#!/usr/bin/env bash
set -uo pipefail
NS=blueking
echo "===== 1. paas3 入口（ingress） ====="
kubectl get ingress -n $NS --no-headers 2>/dev/null | grep -E 'bkpaas3' | awk '{printf "    %-40s %s\n", $1, $2}'

echo ""
echo "===== 2. HTTP 真实探活（走 ingress 域名）====="
# 取 ingress controller 的 NodePort/入口
GW=$(kubectl get svc -n ingress-nginx --no-headers 2>/dev/null | grep -E 'controller' | awk '{print $5}' | head -1)
echo "    网关端口: ${GW:-未直接暴露}"

for h in bkpaas3-webfe-web bkpaas3-apiserver-web; do
  HOST=$(kubectl get ingress $h -n $NS -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)
  [ -z "$HOST" ] && continue
  echo "  --- $h  host=$HOST ---"
  # 从集群内 curl，绕过宿主机 DNS 不通的问题
  kubectl run paas3-probe-$$ -n $NS --rm -i --restart=Never --image=curlimages/curl:8.5.0 --timeout=60s -- \
    curl -s -o /dev/null -w "    HTTP=%{http_code}  耗时=%{time_total}s  大小=%{size_download}\n" \
    -H "Host: $HOST" --max-time 20 http://ingress-nginx-controller.ingress-nginx.svc.cluster.local/ 2>&1 | tail -3
done
