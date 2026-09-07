#!/bin/bash
set -e
P=/mnt/d/projects/learning/grafana/playground/provisioning

echo "=== 全新实例 grafana-prov2 (3003)，allowUiUpdates=true，从零启动 ==="
docker rm -f grafana-prov2 2>/dev/null || echo "no old"

docker run -d --name grafana-prov2 \
  --network grafana-net \
  -p 3003:3000 \
  -v "$P/datasources:/etc/grafana/provisioning/datasources" \
  -v "$P/dashboards:/etc/grafana/provisioning/dashboards" \
  -v "$P/alerting:/etc/grafana/provisioning/alerting" \
  -v "$P/dashboards-json:/var/lib/grafana/dashboards" \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  -e GF_USERS_ALLOW_SIGN_UP=false \
  grafana/grafana:13.2.1

for i in $(seq 1 60); do
  h=$(curl -s --noproxy '*' -m 5 http://localhost:3003/api/health)
  flat=$(printf '%s' "$h" | tr -d ' \n')
  case "$flat" in *'"database":"ok"'*) echo "READY after ${i}x3s"; break;; esac
  sleep 3
done

echo
echo "=== dashboard state (fresh, allowUiUpdates=true) ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3003/api/dashboards/uid/prov-dash-001 > /tmp/l10d2.json
python3 - <<'PY'
import json
d=json.load(open('/tmp/l10d2.json'))
print('  title  =',d['dashboard'].get('title'))
print('  version=',d['dashboard'].get('version'))
print('  meta.provisioned=',d['meta'].get('provisioned'))
print('  meta.provisionedExternalId=',d['meta'].get('provisionedExternalId'))
PY
