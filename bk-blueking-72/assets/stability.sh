#!/usr/bin/env bash
for i in 1 2 3; do
  echo "=== SAMPLE $i  $(date +%H:%M:%S) ==="
  free -m | awk 'NR==2{printf "  mem used=%dMi avail=%dMi (%.1f%%)\n", $3, $7, $3*100/($3+$7)}'
  free -m | awk 'NR==3{printf "  swap used=%dMi\n", $3}'
  echo "  pods=$(kubectl get pods -n blueking --no-headers 2>/dev/null | wc -l) notready=$(kubectl get pods -n blueking --no-headers 2>/dev/null | awk "\$3!=\"Running\" && \$3!=\"Completed\" && \$3!=\"Succeeded\"" | wc -l)"
  echo "  nodes_ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)/3"
  [ $i -lt 3 ] && sleep 45
done
echo ""
echo "=== PSI (memory pressure) ==="
cat /proc/pressure/memory | sed 's/^/  /'
