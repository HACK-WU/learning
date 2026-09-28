#!/usr/bin/env bash
echo "=== TOP 30 PODS BY MEMORY ==="
kubectl top pods -n blueking --no-headers 2>/dev/null | sort -k3 -hr | head -30 | awk '{printf "  %-54s %-9s %s\n", $1, $2, $3}'

echo ""
echo "=== MEMORY PER NAMESPACE ==="
kubectl top pods -A --no-headers 2>/dev/null | awk '{m=$4+0; if($4 ~ /Gi/) m=($4+0)*1024; t[$1]+=m; c[$1]++} END {for(n in t) printf "%d %s %d\n", t[n], n, c[n]}' | sort -rn | awk '{printf "  %-24s pods=%-5d mem=%dMi (%.1fGi)\n", $2, $3, $1, $1/1024}'

echo ""
echo "=== MEMORY BY SUBSYSTEM (blueking) ==="
kubectl top pods -n blueking --no-headers 2>/dev/null | awk '{split($1,p,"-"); pre=p[1]"-"p[2]"-"p[3]; m=$3+0; if($3 ~ /Gi/) m=($3+0)*1024; t[pre]+=m; c[pre]++} END {for(k in t) printf "%d %s %d\n", t[k], k, c[k]}' | sort -rn | head -18 | awk '{printf "  %-30s pods=%-4d mem=%dMi (%.1fGi)\n", $2, $3, $1, $1/1024}'

echo ""
echo "=== NODES TOP ==="
kubectl top nodes --no-headers 2>/dev/null | awk '{printf "  %-32s cpu=%-8s mem=%s\n", $1, $2, $4}'

echo ""
echo "=== HOST MEMORY ==="
free -m | sed 's/^/  /'

echo ""
echo "=== NOT-READY COUNT ==="
echo "  total: $(kubectl get pods -n blueking --no-headers 2>/dev/null | wc -l)"
echo "  not ready: $(kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3 != "Running" && $3 != "Completed" && $3 != "Succeeded"' | wc -l)"
