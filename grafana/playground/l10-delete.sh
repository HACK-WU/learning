#!/bin/bash
D=/var/lib/grafana/dashboards
echo "=== 当前 dashboard 数 ==="
curl -s --noproxy '*' -u admin:admin 'http://localhost:3002/api/search?type=dash-db' | python3 -c "import sys,json;print('  count=',len(json.load(sys.stdin)))"

echo
echo "=== 新加一个文件（模拟 Git 新增） ==="
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
echo "  waiting for updateIntervalSeconds=10 resync..."
sleep 14
curl -s --noproxy '*' -u admin:admin 'http://localhost:3002/api/search?type=dash-db' | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  count=',len(d))
for x in d: print('   ',x.get('uid'),x.get('title'))
"

echo
echo "=== 删除该文件（模拟 Git 删除）—— disableDeletion=false 会怎样? ==="
rm -f /mnt/d/projects/learning/grafana/playground/provisioning/dashboards-json/prov-dash2.json
echo "  waiting for resync..."
sleep 14
curl -s --noproxy '*' -u admin:admin 'http://localhost:3002/api/search?type=dash-db' | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  count=',len(d))
for x in d: print('   ',x.get('uid'),x.get('title'))
"
