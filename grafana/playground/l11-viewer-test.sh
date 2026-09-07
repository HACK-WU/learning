#!/bin/bash
B=http://localhost:3002
U='-u admin:admin'

echo "=== 0. 确认 carol 当前角色 ==="
curl -s --noproxy '*' $U "$B/api/org/users" | python3 -c "
import sys,json
for x in json.load(sys.stdin):
    if x.get('login')=='carol': print('  carol role =',x.get('role'))
"
echo

echo "=== 1. 决定性：carol(Viewer) 往【未授权】的 teamb 建 ==="
curl -s --noproxy '*' -u carol:pass-carol-123 -X POST "$B/api/dashboards/db" \
  -H 'Content-Type: application/json' \
  -d '{"dashboard":{"uid":"carol-vb","title":"Carol Viewer In B","panels":[]},"folderUid":"teamb","overwrite":true}' -o /tmp/v1 -w '  http=%{http_code}\n'
head -c 300 /tmp/v1; echo
echo

echo "=== 2. carol(Viewer) 往 General 建 ==="
curl -s --noproxy '*' -u carol:pass-carol-123 -X POST "$B/api/dashboards/db" \
  -H 'Content-Type: application/json' \
  -d '{"dashboard":{"uid":"carol-vg","title":"Carol Viewer General","panels":[]},"overwrite":true}' -o /tmp/v2 -w '  http=%{http_code}\n'
head -c 300 /tmp/v2; echo
echo

echo "=== 3. bob(Viewer 且不在任何 team) 往 teama 建 ==="
curl -s --noproxy '*' -u bob:pass-bob-123 -X POST "$B/api/dashboards/db" \
  -H 'Content-Type: application/json' \
  -d '{"dashboard":{"uid":"bob-a","title":"Bob In A","panels":[]},"folderUid":"teama","overwrite":true}' -o /tmp/v3 -w '  http=%{http_code}\n'
head -c 300 /tmp/v3; echo
echo

echo "=== 4. 为什么 hasAcl 一直 false？—— 检查是否要用新 RBAC API ==="
echo "  --- 老 API /api/folders/teama/permissions 有记录，但 hasAcl=false ---"
echo "  --- 试新 API: /api/access-control/resource/permissions ---"
curl -s --noproxy '*' $U "$B/api/access-control/resource/dashboards/folders/teama/permissions" -o /tmp/r1 -w '  http=%{http_code}\n' 2>/dev/null
head -c 400 /tmp/r1; echo
echo

echo "=== 5. 试 /api/folders/teama (PUT 更新) 或 检查 managedBy ==="
curl -s --noproxy '*' $U "$B/api/folders/teama" | python3 -m json.tool | head -25
