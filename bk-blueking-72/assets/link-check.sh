#!/usr/bin/env bash
echo "=== LINK HEALTH ==="
echo "  host: $(hostname 2>/dev/null)"
echo "  mem: $(free -m | awk 'NR==2{printf "used=%dMi avail=%dMi", $3, $7}')"
echo ""
echo "  docker daemon:"
pgrep -x dockerd >/dev/null 2>&1 && echo "    dockerd RUNNING" || echo "    dockerd DEAD"
echo ""
echo "  kind node containers:"
for c in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  echo "    $c : $(docker inspect -f '{{.State.Status}}' $c 2>/dev/null)"
done
echo ""
echo "  apiserver reachable:"
kubectl get --raw=/healthz --request-timeout=5s >/dev/null 2>&1 && echo "    YES" || echo "    NO (connection refused)"
echo ""
echo "  nodes:"
kubectl get nodes --no-headers 2>&1 | head -4 | sed 's/^/    /'
