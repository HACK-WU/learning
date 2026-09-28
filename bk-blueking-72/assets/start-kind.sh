#!/usr/bin/env bash
echo "=== START KIND NODES ==="
for c in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)
  echo "  $c : $st"
  [ "$st" != "running" ] && docker start "$c" >/dev/null 2>&1 && echo "    -> started"
done
echo ""
echo "=== WAIT 90s ==="
sleep 90
echo ""
echo "=== VERIFY ==="
kubectl get nodes --no-headers 2>&1 | awk '{printf "  %-30s %s\n", $1, $2}'
echo "  pods: $(kubectl get pods -n blueking --no-headers 2>/dev/null | wc -l)"
echo ""
echo "=== MEM AFTER ==="
echo "  host: $(free -m | awk 'NR==2{printf "used=%dMi avail=%dMi", $3,$7}')"
kubectl top nodes --no-headers 2>/dev/null | awk '{printf "  %-30s cpu=%-8s mem=%s\n", $1, $2, $4}'
