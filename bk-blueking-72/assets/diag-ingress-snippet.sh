#!/usr/bin/env bash
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH

echo "===== 1. ingress-nginx 相关资源 ====="
kubectl get ns --no-headers 2>/dev/null | grep -iE 'ingress' | sed 's/^/  /'
echo "  --- deployment ---"
kubectl get deploy -A --no-headers 2>/dev/null | grep -iE 'ingress-nginx|nginx-ingress' | awk '{print "  "$1" "$2}'
echo "  --- configmap ---"
kubectl get cm -A --no-headers 2>/dev/null | grep -iE 'ingress' | awk '{print "  "$1" "$2}'

echo ""
echo "===== 2. 找出 nginx 使用的 configmap 名（controller 启动参数）====="
kubectl get deploy -A --no-headers 2>/dev/null | grep -iE 'ingress-nginx|nginx-ingress' | awk '{print $1" "$2}' | while read ns d; do
  echo "  --- $ns/$d ---"
  kubectl get deploy "$d" -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null | tr ',' '\n' | grep -E 'configmap|controller-class' | sed 's/^/    /'
done

echo ""
echo "===== 3. configmap 当前 data（看 allow-snippet 现状）====="
kubectl get deploy -A --no-headers 2>/dev/null | grep -iE 'ingress-nginx|nginx-ingress' | awk '{print $1" "$2}' | while read ns d; do
  CM=$(kubectl get deploy "$d" -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null | tr ' ' '\n' | grep -A0 'configmap' | sed 's/.*=//')
  CM=${CM:-$(kubectl get deploy "$d" -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null | tr ',' '\n' | grep 'configmap' | sed 's/.*=//')}
  [ -n "$CM" ] && {
    echo "  ns=$ns cm=$CM"
    kubectl get cm "$CM" -n "$ns" -o yaml 2>/dev/null | sed -n '/^data:/,/^kind:/p' | sed 's/^/    /'
    echo "    --- 全文 grep snippet ---"
    kubectl get cm "$CM" -n "$ns" -o yaml 2>/dev/null | grep -iE 'snippet|allow' | sed 's/^/    /' || echo "    (无 snippet 配置)"
  }
done

echo ""
echo "===== 4. 哪些 ingress 用了 server-snippet（second 批会创建的）====="
kubectl get ingress -A -o json 2>/dev/null | grep -oE '"nginx.ingress.kubernetes.io/[a-z-]*snippet[a-z-]*"' | sort | uniq -c | sed 's/^/  /'

echo ""
echo "===== 5. validating webhook 配置 ====="
kubectl get validatingwebhookconfigurations --no-headers 2>/dev/null | grep -iE 'ingress|nginx' | awk '{print "  "$1}'
