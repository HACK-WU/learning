#!/usr/bin/env bash
NS=blueking
echo "=== LINK ==="
kubectl get nodes --no-headers 2>&1 | head -2 | sed 's/^/  /'
echo ""
echo "=== READY SUMMARY ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '{n++; split($2,a,"/"); r=a[1]+0; d=a[2]+0; if(r>0) live++; else dead++} END {printf "  total=%d ready>0=%d ready=0=%d\n", n, live, dead}'
echo ""
echo "=== READY=0 LIST ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '{split($2,a,"/"); if(a[1]+0==0) printf "    %-48s raw=%s\n", $1, $2}' | sort
echo ""
echo "=== MEM ==="
free -m | awk 'NR==2{printf "  used=%dMi avail=%dMi (%.1f%%)\n", $3, $7, $3*100/($3+$7)}'
