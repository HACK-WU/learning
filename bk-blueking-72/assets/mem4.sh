#!/usr/bin/env bash
echo "=== POD RECOVERY CHECK ==="
echo "  total blueking pods: $(kubectl get pods -n blueking --no-headers 2>/dev/null | wc -l)"
echo ""
echo "=== NOT READY ==="
kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3 != "Running" && $3 != "Completed" && $3 != "Succeeded" {printf "  %-48s %-12s %s\n", $1, $2, $3}'
echo "  (empty = all ready)"

echo ""
echo "=== MEMORY: NODE ALLOCATED ==="
for n in $(kubectl get nodes --no-headers 2>/dev/null | awk '{print $1}'); do
  echo "  node=$n"
  kubectl describe node "$n" 2>/dev/null | grep -A6 'Allocated resources' | grep -E 'cpu|memory' | sed 's/^/    /'
done

echo ""
echo "=== HOST MEMORY (WSL) ==="
free -m | sed 's/^/  /'

echo ""
echo "=== METRICS AVAILABLE? ==="
kubectl top nodes 2>&1 | head -3 | sed 's/^/  /'
