#!/bin/bash
echo "=== containers ==="
docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -Ei 'grafana|loki|jaeger|prom' || echo "none"
echo
echo "=== health 3001/3002/3003 ==="
for p in 3001 3002 3003; do
  printf "  %s: " "$p"
  curl -s --noproxy '*' -m 5 http://localhost:$p/api/health | tr -d ' \n'
  echo
done
echo
echo "=== orgs on 3002 ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3002/api/orgs 2>/dev/null | head -c 400
echo
echo
echo "=== users on 3002 ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3002/api/org/users 2>/dev/null | head -c 600
echo
