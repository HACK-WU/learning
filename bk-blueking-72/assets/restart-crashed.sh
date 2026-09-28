#!/usr/bin/env bash
NS=blueking
echo "=== RESTART CRASHED / UNKNOWN PODS ==="
for p in $(kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3=="CrashLoopBackOff" || $3=="Error" || $3=="Unknown" {print $1}'); do
  echo "  restart: $p"
  kubectl delete pod "$p" -n $NS --grace-period=0 --force >/dev/null 2>&1
  sleep 3
done

echo ""
echo "=== WAIT 120s ==="
sleep 120

echo ""
echo "=== RECHECK ==="
echo "  total: $(kubectl get pods -n $NS --no-headers 2>/dev/null | wc -l)"
echo "  not-ready: $(kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed" && $3!="Succeeded"' | wc -l)"
echo ""
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed" && $3!="Succeeded" {printf "  %-52s %-10s %s\n", $1, $2, $3}'
echo ""
echo "=== MEM ==="
free -m | sed 's/^/  /'
