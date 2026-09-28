#!/usr/bin/env bash
NS=blueking
echo "=== NOT READY ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed" && $3!="Succeeded" {printf "  %-52s %-10s %s\n", $1, $2, $3}'
echo ""
echo "=== NODES ==="
kubectl get nodes --no-headers 2>&1 | awk '{printf "  %-30s %s\n", $1, $2}'
echo ""
echo "=== MEM ==="
free -m | awk 'NR==2{printf "  mem  used=%dMi avail=%dMi (%.1f%%)\n", $3, $7, $3*100/($3+$7)}'
free -m | awk 'NR==3{printf "  swap used=%dMi\n", $3}'
echo "  psi:"
cat /proc/pressure/memory | sed 's/^/    /'
echo ""
echo "=== TOP MEM PODS ==="
kubectl top pods -n $NS --no-headers 2>/dev/null | sort -k3 -hr | head -10 | awk '{printf "  %-50s %s\n", $1, $3}'
