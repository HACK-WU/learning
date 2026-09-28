#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. ingress-nginx ClusterIP（集群内 Pod 应走这个，不是 NodePort）====="
CIP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
echo "  ClusterIP = $CIP"
echo "  Type      = $(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.type}')"
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{range .spec.ports[*]}  {$protocol}{": "}{.port}{" -> "}{.targetPort}{"\n"}{end}'

echo ""
echo "===== 2. coredns 可用插件（确认有 template）====="
for p in $(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep dns | awk '{print $1}'); do
  echo "  --- $p ---"
  kubectl exec $p -n kube-system -- /coredns -plugins 2>/dev/null | grep -E 'template|hosts|rewrite' | sed 's/^/    /'
done

echo ""
echo "===== 3. 从 paas3-dbg 实测：ingress ClusterIP:80 能不能通 ====="
echo "  当前解析 bkiam.paas.example.com:"
kubectl exec paas3-dbg -n $NS -- getent hosts bkiam.paas.example.com 2>&1 | sed 's/^/    /' || echo "    解析失败（预期）"
echo "  直连 ingress ClusterIP:80（带 Host 头）:"
kubectl exec paas3-dbg -n $NS -- bash -c "curl -s -o /dev/null -w '    HTTP %{http_code}\n' --max-time 8 -H 'Host: bkiam.paas.example.com' http://${CIP}/" 2>&1 | sed 's/^/  /'

echo ""
echo "===== 4. 备份当前 Corefile ====="
kubectl get cm coredns -n kube-system -o yaml > /root/bk72/install/coredns-backup-$(date +%Y%m%d-%H%M%S).yaml 2>/dev/null
ls -la /root/bk72/install/coredns-backup-*.yaml 2>/dev/null | tail -3 | awk '{print "  "$9}'

echo ""
echo "===== 5. 两个 CrashLoop 的 iam Job 报错（可能是同一根因）====="
for p in $(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'bkiam-saas-(apigateway-sync|synchronization)' | awk '{print $1}'); do
  echo "  --- $p ---"
  kubectl logs $p -n $NS --tail=6 2>&1 | grep -viE '^\s*$' | tail -4 | sed 's/^/    /'
done
