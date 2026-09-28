#!/usr/bin/env bash
echo "=== RECOVER CLUSTER ==="
for c in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)
  echo "  $c : $st"
  [ "$st" != "running" ] && docker start "$c" >/dev/null 2>&1 && echo "    -> started"
done
echo "  waiting 120s ..."
sleep 120

echo ""
echo "=== VERIFY ==="
echo "  nodes:"
kubectl get nodes --no-headers 2>&1 | head -3 | awk '{printf "    %-30s %s\n", $1, $2}'
echo ""
echo "  pods: total=$(kubectl get pods -n blueking --no-headers 2>/dev/null | wc -l) notready=$(kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed" && $3!="Succeeded"' | wc -l)"
echo ""
echo "  rbac hooks:"
docker exec k8s-c1-calico-control-plane bash -c 'curl -sk https://127.0.0.1:6443/healthz --max-time 8' 2>&1 | grep -cE '^\[-\]' | sed 's/^/    failed hooks: /'
echo ""
free -m | awk 'NR==2{printf "  mem used=%dMi avail=%dMi\n", $3, $7}'
