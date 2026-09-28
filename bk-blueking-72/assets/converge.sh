#!/usr/bin/env bash
echo "=== CONVERGENCE CHECK (single sample) ==="
echo "  time: $(date +%H:%M:%S)"
echo ""
free -m | awk 'NR==2{printf "  mem    used=%dMi avail=%dMi (%.1f%%)\n", $3, $7, $3*100/($3+$7)}'
free -m | awk 'NR==3{printf "  swap   used=%dMi\n", $3}'
echo "  nodes  ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)/3"
echo "  pods   total=$(kubectl get pods -n blueking --no-headers 2>/dev/null | wc -l)"
echo "  notready=$(kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed" && $3!="Succeeded"' | wc -l)"
echo ""
echo "  --- not-ready detail ---"
kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed" && $3!="Succeeded" {printf "    %-52s %-8s %s\n", $1, $2, $3}' | head -20
echo ""
echo "  --- PSI ---"
cat /proc/pressure/memory | sed 's/^/    /'
echo ""
echo "  --- vmmem (host side) ---"
echo "    (check from PowerShell separately)"
