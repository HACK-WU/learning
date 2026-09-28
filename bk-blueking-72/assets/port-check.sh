#!/usr/bin/env bash
echo "=== PORT FORWARDING DIAGNOSIS ==="
echo "--- listen 40271 on WSL ---"
(ss -ltnp 2>/dev/null || netstat -ltnp 2>/dev/null) | grep -E '40271|6443' | sed 's/^/  /'
echo "  (empty = nothing listening)"
echo ""
echo "--- docker port mapping ---"
docker port k8s-c1-calico-control-plane 2>&1 | head -5 | sed 's/^/  /'
echo ""
echo "--- control-plane container IP ---"
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' k8s-c1-calico-control-plane 2>&1 | sed 's/^/  /'
echo ""
echo "--- apiserver health INSIDE container ---"
docker exec k8s-c1-calico-control-plane bash -c 'curl -sk https://127.0.0.1:6443/healthz --max-time 5' 2>&1 | sed 's/^/  /'
echo ""
echo "--- apiserver process ---"
docker exec k8s-c1-calico-control-plane bash -c 'ps aux 2>/dev/null | grep -c kube-apiserver' 2>&1 | sed 's/^/  /'
echo ""
echo "--- try direct via container IP ---"
CPIP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' k8s-c1-calico-control-plane 2>/dev/null)
echo "  CPIP=$CPIP"
curl -sk "https://$CPIP:6443/healthz" --max-time 5 2>&1 | sed 's/^/  /'
