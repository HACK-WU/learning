#!/usr/bin/env bash
echo "=== 1. NODES (top) ==="
timeout 60 kubectl top nodes 2>&1 | sed 's/^/  /'

echo ""
echo "=== 2. NODE ALLOCATED RESOURCES ==="
timeout 60 kubectl describe node 2>&1 | grep -A8 "Allocated resources" | head -40 | sed 's/^/  /'

echo ""
echo "=== 3. TOP 30 PODS BY MEMORY (blueking) ==="
timeout 90 kubectl top pods -n blueking --no-headers 2>&1 | sort -k3 -hr | head -30 | awk '{printf "  %-54s %-8s %s\n", $1, $2, $3}'

echo ""
echo "=== 4. MEMORY PER NAMESPACE (Mi) ==="
timeout 90 kubectl top pods -A --no-headers 2>&1 | awk '{m=$4+0; if($4 ~ /Gi/) m=($4+0)*1024; t[$1]+=m; c[$1]++} END {for(n in t) printf "  %-24s pods=%-4d mem=%dMi (%.1fGi)\n", n, c[n], t[n], t[n]/1024}' | sort -t= -k3 -rn

echo ""
echo "=== 5. OOM / EVICTED PODS ==="
kubectl get pods -A --no-headers 2>/dev/null | grep -iE 'oom|evicted' | head -10 | sed 's/^/  /'
echo "  (empty = none)"

echo ""
echo "=== 6. MEMORY-RELATED EVENTS ==="
kubectl get events -A --sort-by='.lastTimestamp' 2>/dev/null | grep -iE 'memory|oom|evict|pressure' | tail -10 | cut -c1-150 | sed 's/^/  /'

echo ""
echo "=== 7. REPLICAS PER SUBSYSTEM (blueking) ==="
kubectl get deploy -n blueking --no-headers 2>/dev/null | awk '{n=$1; split(n,p,"-"); pre=p[1]"-"p[2]; split($2,r,"/"); cnt[pre]+=r[2]} END {for(k in cnt) printf "  %-30s replicas=%d\n", k, cnt[k]}' | sort -t= -k2 -rn

echo ""
echo "=== 8. TOTAL PODS ==="
echo "  blueking pods: $(kubectl get pods -n blueking --no-headers 2>/dev/null | wc -l)"
echo "  all pods:      $(kubectl get pods -A --no-headers 2>/dev/null | wc -l)"
