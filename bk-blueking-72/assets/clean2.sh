#!/usr/bin/env bash
NS=blueking
echo "=== CLEAN ROUND ==="
LIST=$(kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3=="Unknown" || $3=="CrashLoopBackOff" || $3=="Error" {print $1}')
echo "  to clean: $(echo "$LIST" | grep -c .)"
for p in $LIST; do kubectl delete pod "$p" -n $NS --grace-period=0 --force >/dev/null 2>&1; done
echo "  waiting 180s ..."
sleep 180

echo ""
echo "=== STATE ==="
echo "  nodes: $(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"{c++} END{print c+0}')/3 ready"
echo "  pods total:  $(kubectl get pods -n $NS --no-headers 2>/dev/null | wc -l)"
echo "  not ready:   $(kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed" && $3!="Succeeded"' | wc -l)"
echo ""
echo "  --- remaining not-ready (first 15) ---"
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed" && $3!="Succeeded" {printf "    %-50s %s\n", $1, $3}' | head -15
echo ""
free -m | awk 'NR==2{printf "  mem  used=%dMi avail=%dMi (%.1f%%)\n", $3, $7, $3*100/($3+$7)}'
free -m | awk 'NR==3{printf "  swap used=%dMi\n", $3}'
