#!/usr/bin/env bash
echo "=== $(date +%H:%M:%S) SAMPLE ==="
echo "  host: $(free -m | awk 'NR==2{printf "total=%dMi used=%dMi available=%dMi", $2,$3,$7}')"
echo "  swap: $(free -m | awk 'NR==3{printf "used=%dMi", $3}')"
echo "  nodes:"
kubectl top nodes --no-headers 2>/dev/null | awk '{printf "    %-30s cpu=%-8s mem=%s\n", $1, $2, $4}'
echo "  blueking total: $(kubectl top pods -n blueking --no-headers 2>/dev/null | awk '{m=$3+0; if($3 ~ /Gi/) m=m*1024; s+=m} END {printf "%dMi (%.1fGi)", s, s/1024}')"
echo "  not-ready: $(kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3 != "Running" && $3 != "Completed" && $3 != "Succeeded"' | wc -l)"
