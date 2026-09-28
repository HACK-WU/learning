#!/usr/bin/env bash
echo "=== ELASTICSEARCH ==="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -i elastic | awk '{printf "  %-50s %-10s %s\n", $1, $2, $3}'
echo ""
echo "=== ES SVC/ENDPOINT ==="
kubectl get svc -n blueking --no-headers 2>/dev/null | grep -i elastic | awk '{printf "  %-46s %-16s %s\n", $1, $2, $5}'
kubectl get endpoints -n blueking 2>/dev/null | grep -i elastic | sed 's/^/  /'
echo ""
echo "=== ES LOG (master) ==="
kubectl logs bk-elastic-elasticsearch-master-0 -n blueking --tail=12 2>&1 | cut -c1-150 | sed 's/^/  /'
echo ""
echo "=== WAITING? check other Crashed ==="
for p in bk-cmdb-adminserver bk-repo-bkrepo-job bkiam-search-engine-rbac-0 bk-monitor-ingester; do
  echo "  --- $p ---"
  kubectl logs $p -n blueking --tail=6 2>&1 | cut -c1-140 | sed 's/^/    /'
done
