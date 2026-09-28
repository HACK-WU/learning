#!/usr/bin/env bash
NS=blueking
echo "=== REAL POD COUNT ==="
T=$(kubectl get pods -n $NS --no-headers 2>/dev/null | wc -l)
echo "  total: $T"
echo "  Running: $(kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3=="Running"' | wc -l)"
echo "  Completed: $(kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3=="Completed"' | wc -l)"
echo "  Pending: $(kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3=="Pending"' | wc -l)"
echo ""
echo "  node Ready count: $(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"{c++} END{print c+0}')"
echo ""
echo "=== MEM ==="
free -m | sed 's/^/  /'
echo ""
echo "=== KIND CONTAINERS (the real RAM consumer) ==="
docker stats --no-stream --format '{{.Name}}|{{.MemUsage}}' 2>/dev/null | grep -E 'k8s-c1-calico' | sed 's/^/  /'
echo ""
echo "=== HOST SIDE (Windows vmmem) ==="
echo "  check via PowerShell: Get-Process vmmemWSL"
