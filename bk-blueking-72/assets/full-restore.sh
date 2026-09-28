#!/usr/bin/env bash
# 完整恢复 + 严谨收敛验证
echo "=== STEP 1: ensure containers up ==="
for c in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)
  [ "$st" != "running" ] && docker start "$c" >/dev/null 2>&1 && echo "  started $c"
done

echo ""
echo "=== STEP 2: wait for apiserver (poll up to 300s) ==="
for i in $(seq 1 30); do
  if kubectl get nodes --no-headers >/dev/null 2>&1; then
    echo "  apiserver OK after ${i}0s"
    break
  fi
  sleep 10
done

echo ""
echo "=== STEP 3: wait for pods to appear (poll up to 300s) ==="
for i in $(seq 1 30); do
  N=$(kubectl get pods -n blueking --no-headers 2>/dev/null | wc -l)
  if [ "$N" -gt 150 ]; then
    echo "  pods registered: $N after ${i}0s"
    break
  fi
  sleep 10
done

echo ""
echo "=== STEP 4: wait for convergence (poll until notready stable) ==="
PREV=-1
for i in $(seq 1 40); do
  NR=$(kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed" && $3!="Succeeded"' | wc -l)
  T=$(kubectl get pods -n blueking --no-headers 2>/dev/null | wc -l)
  echo "  t=${i}0s total=$T notready=$NR"
  [ "$T" -gt 0 ] && [ "$NR" -eq 0 ] && { echo "  CONVERGED"; break; }
  sleep 10
done

echo ""
echo "=== STEP 5: FINAL MEASUREMENT ==="
echo "  nodes: $(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"{c++} END{print c+0}')/3"
echo "  pods:  $(kubectl get pods -n blueking --no-headers 2>/dev/null | wc -l)"
echo "  notready: $(kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed" && $3!="Succeeded"' | wc -l)"
free -m | awk 'NR==2{printf "  mem  used=%dMi avail=%dMi (%.1f%%)\n", $3, $7, $3*100/($3+$7)}'
free -m | awk 'NR==3{printf "  swap used=%dMi\n", $3}'
cat /proc/pressure/memory | sed 's/^/  /'
