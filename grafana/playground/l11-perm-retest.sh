#!/bin/bash
B=http://localhost:3002
U='-u admin:admin'

echo "=== 1. carol(Editor) 用正确写法往 teama（已授权 Edit）建 dashboard ==="
curl -s --noproxy '*' -u carol:pass-carol-123 -X POST "$B/api/dashboards/db" \
  -H 'Content-Type: application/json' \
  -d '{"dashboard":{"uid":"carol-a","title":"Carol In A","panels":[]},"folderUid":"teama","overwrite":false}' -o /tmp/ca -w '  http=%{http_code}\n'
head -c 300 /tmp/ca; echo
echo

echo "=== 2. carol 往 teamb（未授权）建 ==="
curl -s --noproxy '*' -u carol:pass-carol-123 -X POST "$B/api/dashboards/db" \
  -H 'Content-Type: application/json' \
  -d '{"dashboard":{"uid":"carol-b","title":"Carol In B","panels":[]},"folderUid":"teamb","overwrite":false}' -o /tmp/cb -w '  http=%{http_code}\n'
head -c 300 /tmp/cb; echo
echo

echo "=== 3. carol 往 General 建（无文件夹权限但有 Editor 角色）==="
curl -s --noproxy '*' -u carol:pass-carol-123 -X POST "$B/api/dashboards/db" \
  -H 'Content-Type: application/json' \
  -d '{"dashboard":{"uid":"carol-g","title":"Carol In General","panels":[]},"overwrite":false}' -o /tmp/cg -w '  http=%{http_code}\n'
head -c 300 /tmp/cg; echo
echo

echo "=== 4. hasAcl 复查 ==="
for f in teama teamb; do
  printf "  %s: " "$f"
  curl -s --noproxy '*' $U "$B/api/folders/$f" | python3 -c "import sys,json;print('hasAcl=',json.load(sys.stdin).get('hasAcl'))"
done
echo

echo "=== 5. 关键对照：把 carol 降回 Viewer，只靠文件夹权限 ==="
curl -s --noproxy '*' $U -X PATCH "$B/api/org/users/4" \
  -H 'Content-Type: application/json' -d '{"role":"Viewer"}' -o /dev/null -w '  demote http=%{http_code}\n'
echo "  --- carol(Viewer + teama Edit) 往 teama 建 ---"
curl -s --noproxy '*' -u carol:pass-carol-123 -X POST "$B/api/dashboards/db" \
  -H 'Content-Type: application/json' \
  -d '{"dashboard":{"uid":"carol-v","title":"Carol Viewer In A","panels":[]},"folderUid":"teama","overwrite":true}' -o /tmp/cv -w '  http=%{http_code}\n'
head -c 300 /tmp/cv; echo
