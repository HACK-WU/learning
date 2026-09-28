#!/usr/bin/env bash
echo "=== WSL / DOCKER / CLUSTER HEALTH ==="
echo "  host mem: $(free -m | awk 'NR==2{printf "total=%dMi used=%dMi avail=%dMi", $2,$3,$7}')"
echo "  swap: $(free -m | awk 'NR==3{printf "used=%dMi", $3}')"
echo ""
echo "  kind nodes (docker):"
for c in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  echo "    $c : $(docker inspect -f '{{.State.Status}}' $c 2>/dev/null)"
done
echo ""
echo "  kubectl nodes:"
kubectl get nodes --no-headers 2>&1 | awk '{printf "    %-30s %s\n", $1, $2}'
echo ""
echo "  blueking pods: $(kubectl get pods -n blueking --no-headers 2>/dev/null | wc -l)"
echo "  not-ready: $(kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3 != "Running" && $3 != "Completed" && $3 != "Succeeded"' | wc -l)"
