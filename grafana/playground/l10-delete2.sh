#!/bin/bash
echo "=== restart prov2 (3003) with disableDeletion=true ==="
docker restart grafana-prov2
for i in $(seq 1 60); do
  h=$(curl -s --noproxy '*' -m 5 http://localhost:3003/api/health)
  flat=$(printf '%s' "$h" | tr -d ' \n')
  case "$flat" in *'"database":"ok"'*) echo "  ready"; break;; esac
  sleep 3
done

echo
echo "=== add dash2 file again on prov2 ==="
cat > /mnt/d/projects/learning/grafana/playground/provisioning/dashboards-json/prov-dash2.json <<'JSON'
{
  "uid": "prov-dash-002",
  "title": "Second Provisioned Dash",
  "schemaVersion": 41,
  "panels": [],
  "time": { "from": "now-1h", "to": "now" },
  "templating": { "list": [] },
  "annotations": { "list": [] },
  "links": []
}
JSON
sleep 14
curl -s --noproxy '*' -u admin:admin 'http://localhost:3003/api/search?type=dash-db' | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  count=',len(d))
for x in d: print('   ',x.get('uid'),x.get('title'))
"

echo
echo "=== delete file, disableDeletion=true => should SURVIVE ==="
rm -f /mnt/d/projects/learning/grafana/playground/provisioning/dashboards-json/prov-dash2.json
sleep 14
curl -s --noproxy '*' -u admin:admin 'http://localhost:3003/api/search?type=dash-db' | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  count=',len(d))
for x in d: print('   ',x.get('uid'),x.get('title'))
"
