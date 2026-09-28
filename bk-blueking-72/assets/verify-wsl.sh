#!/usr/bin/env bash
echo "=== WSL MEMORY NEW CONFIG ==="
free -m | sed 's/^/  /'
echo ""
echo "=== SWAP ==="
swapon --show | sed 's/^/  /'
echo ""
echo "=== KIND NODES ==="
for c in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  echo "  $c : $(docker inspect -f '{{.State.Status}}' $c 2>/dev/null)"
done
echo ""
echo "=== KUBECTL ==="
kubectl get nodes --no-headers 2>&1 | awk '{printf "  %-30s %s\n", $1, $2}'
echo "  blueking pods: $(kubectl get pods -n blueking --no-headers 2>/dev/null | wc -l)"
