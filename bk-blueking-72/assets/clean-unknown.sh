#!/usr/bin/env bash
NS=blueking
echo "=== CLEAN UNKNOWN / CRASHED PODS ==="
LIST=$(kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3=="Unknown" || $3=="CrashLoopBackOff" || $3=="Error" {print $1}')
N=$(echo "$LIST" | grep -c .)
echo "  to clean: $N"
for p in $LIST; do
  kubectl delete pod "$p" -n $NS --grace-period=0 --force >/dev/null 2>&1
done
echo "  deleted. waiting 150s ..."
sleep 150

echo ""
echo "=== RECHECK ==="
echo "  nodes ready: $(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)/3"
echo "  pods total:  $(kubectl get pods -n $NS --no-headers 2>/dev/null | wc -l)"
echo "  not ready:   $(kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed" && $3!="Succeeded"' | wc -l)"
echo ""
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed" && $3!="Succeeded" {printf "  %-52s %-8s %s\n", $1, $2, $3}' | head -15
echo ""
echo "=== MEM ==="
free -m | awk 'NR==2{printf "  mem  used=%dMi avail=%dMi (%.1f%%)\n", $3, $7, $3*100/($3+$7)}'
free -m | awk 'NR==3{printf "  swap used=%dMi\n", $3}'
cat /proc/pressure/memory | sed 's/^/  /'
