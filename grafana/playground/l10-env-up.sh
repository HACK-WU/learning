#!/bin/bash
set -e
P=/mnt/d/projects/learning/grafana/playground/provisioning

echo "=== 0. verify files exist (docker -v would silently mkdir) ==="
for f in "$P/datasources/ds.yaml" "$P/dashboards/dash.yaml" "$P/alerting/alerts.yaml" "$P/dashboards-json/prov-dash.json"; do
  if [ -f "$f" ]; then echo "OK file: $f"; else echo "MISSING: $f"; exit 1; fi
done

echo
echo "=== 1. remove old ==="
docker rm -f grafana-prov 2>/dev/null || echo "no old container"

echo
echo "=== 2. run grafana-prov ==="
docker run -d --name grafana-prov \
  --network grafana-net \
  -p 3002:3000 \
  -v "$P/datasources:/etc/grafana/provisioning/datasources" \
  -v "$P/dashboards:/etc/grafana/provisioning/dashboards" \
  -v "$P/alerting:/etc/grafana/provisioning/alerting" \
  -v "$P/dashboards-json:/var/lib/grafana/dashboards" \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  -e GF_USERS_ALLOW_SIGN_UP=false \
  grafana/grafana:13.2.1

echo
echo "=== 3. wait ready ==="
for i in $(seq 1 90); do
  h=$(curl -s --noproxy '*' http://localhost:3002/api/health)
  flat=$(printf '%s' "$h" | tr -d ' \n')
  if printf '%s' "$flat" | grep -q '"database":"ok"'; then
    echo "ready after ${i}x2s: $flat"
    break
  fi
  sleep 2
done
echo "final health: $h"
