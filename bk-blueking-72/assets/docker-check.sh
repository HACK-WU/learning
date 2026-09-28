#!/usr/bin/env bash
echo "=== ALL CONTAINERS (docker) ==="
docker ps -a --format '{{.Names}}|{{.Status}}' 2>&1 | sed 's/^/  /'

echo ""
echo "=== KIND CLUSTERS ==="
kind get clusters 2>&1 | sed 's/^/  /'

echo ""
echo "=== KUBECTL CONTEXT / CONFIG ==="
kubectl config current-context 2>&1 | sed 's/^/  /'
kubectl config view --minify 2>&1 | grep -E 'server|cluster' | sed 's/^/  /'

echo ""
echo "=== NODE REACHABLE? ==="
kubectl get nodes 2>&1 | head -5 | sed 's/^/  /'
