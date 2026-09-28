#!/usr/bin/env bash
echo "=== RESTORE KIND CLUSTER NODES ==="
for c in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)
  echo "  $c : $st"
  if [ "$st" != "running" ]; then
    docker start "$c" 2>&1 | sed 's/^/    start -> /'
  fi
done

echo ""
echo "=== WAIT 60s ==="
sleep 60

echo ""
echo "=== CHECK ==="
docker ps --format '{{.Names}}|{{.Status}}' 2>&1 | grep -E 'k8s-c1-calico' | sed 's/^/  /'
echo ""
kubectl get nodes 2>&1 | head -6 | sed 's/^/  /'
