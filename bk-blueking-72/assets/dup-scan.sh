#!/usr/bin/env bash
NS=blueking
echo "=== ALL WORKLOADS (deploy/sts/ds) ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '{printf "  deploy  %-52s %s/%s\n", $1, $3, $4}' | sort
echo ""
kubectl get sts -n $NS --no-headers 2>/dev/null | awk '{printf "  sts     %-52s %s/%s\n", $1, $3, $4}' | sort
echo ""
kubectl get ds -n $NS --no-headers 2>/dev/null | awk '{printf "  ds      %-52s %s\n", $1, $4}' | sort
