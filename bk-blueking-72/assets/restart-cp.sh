#!/usr/bin/env bash
echo "=== RESTART CONTROL-PLANE ==="
docker restart k8s-c1-calico-control-plane 2>&1 | sed 's/^/  /'
echo "  waiting 100s ..."
sleep 100
echo ""
echo "=== VERIFY ==="
echo "--- apiserver health inside ---"
docker exec k8s-c1-calico-control-plane bash -c 'curl -sk https://127.0.0.1:6443/healthz --max-time 8' 2>&1 | sed 's/^/  /'
echo ""
echo "--- via 40271 ---"
kubectl get nodes --no-headers 2>&1 | head -4 | sed 's/^/  /'
echo ""
echo "--- pods ---"
echo "  total: $(kubectl get pods -n blueking --no-headers 2>/dev/null | wc -l)"
echo "  notready: $(kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed" && $3!="Succeeded"' | wc -l)"
echo ""
echo "--- mem ---"
free -m | awk 'NR==2{printf "  used=%dMi avail=%dMi\n", $3, $7}'
