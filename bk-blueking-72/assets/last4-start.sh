#!/usr/bin/env bash
NS=blueking
D="bkiam-saas-beat bkiam-saas-worker bk-apigateway-dashboard-beat bk-apigateway-dashboard-celery"

echo "=== 启动 4 个（无探针，不会被误杀） ==="
for d in $D; do
  kubectl scale deploy -n $NS $d --replicas=1 >/dev/null 2>&1 && echo "  scaled $d"
done

echo ""
echo "=== 等 150s ==="
sleep 150

echo ""
echo "=== 状态 ==="
for d in $D; do
  s=$(kubectl get deploy -n $NS $d --no-headers 2>/dev/null | awk '{print $2}')
  p=$(kubectl get pods -n $NS -l app.kubernetes.io/name=$d --no-headers 2>/dev/null | head -1 | awk '{print $3}')
  printf "    %-34s deploy=%-6s pod=%s\n" "$d" "$s" "${p:-?}"
done

echo ""
echo "=== 所有 pod 里这 4 个的真实状态 ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'bkiam-saas-(beat|worker)|apigateway-dashboard-(beat|celery)' | awk '{printf "    %-46s %-10s restarts=%s\n",$1,$3,$4}'

echo ""
echo "=== 内存 ==="
free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'
