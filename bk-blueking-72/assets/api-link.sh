#!/usr/bin/env bash
echo "=== API LINK ==="
kubectl get nodes --no-headers 2>&1 | head -3 | sed 's/^/  /'
echo ""
echo "=== CP CONTAINER ==="
docker inspect -f '{{.State.Status}} (restart={{.RestartCount}})' k8s-c1-calico-control-plane 2>&1 | sed 's/^/  /'
echo "  started: $(docker inspect -f '{{.State.StartedAt}}' k8s-c1-calico-control-plane 2>&1)"
echo ""
echo "=== APISERVER HEALTH ==="
docker exec k8s-c1-calico-control-plane bash -c 'curl -sk https://127.0.0.1:6443/healthz --max-time 8' 2>&1 | sed 's/^/  /'
echo ""
echo "=== APISERVER RESTARTS (etcd health) ==="
docker exec k8s-c1-calico-control-plane bash -c 'crictl ps -a 2>/dev/null | grep -E "apiserver|etcd" | head -6' 2>&1 | cut -c1-140 | sed 's/^/  /'
echo ""
echo "=== ETCD ==="
docker exec k8s-c1-calico-control-plane bash -c 'curl -sk https://127.0.0.1:2379/health --max-time 5' 2>&1 | sed 's/^/  /'
echo ""
echo "=== CP MEM (container level) ==="
docker stats --no-stream --format '{{.Name}}  {{.MemUsage}}' k8s-c1-calico-control-plane 2>&1 | sed 's/^/  /'
