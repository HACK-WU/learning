#!/bin/bash
B=http://localhost:3002
U='-u admin:admin'

echo "=== 1. carol 创建了哪些 dashboard ==="
curl -s --noproxy '*' $U "$B/api/search?type=dash-db" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  total=',len(d))
for x in d: print('   %-24s folder=%s' % (x.get('uid'),x.get('folderTitle')))
"
echo

echo "=== 2. dave 加入 team 后，给他 teama 的 Edit，再看权限 ==="
curl -s --noproxy '*' $U -X POST "$B/api/folders/teama/permissions" \
  -H 'Content-Type: application/json' -d '{"items":[{"teamId":2,"permission":2}]}' -o /dev/null -w '  grant http=%{http_code}\n'
sleep 2
echo "  --- dave(Viewer, TeamBGroup, teama=Edit) ---"
curl -s --noproxy '*' -u dave:pass-dave-123 "$B/api/access-control/user/permissions" 2>/dev/null | python3 -c "
import sys,json;d=json.load(sys.stdin)
print('   ',sorted([k for k in d.keys() if k.startswith('dashboards:') or k.startswith('folders:')]))
"
echo
echo "  --- dave 往 teama 建 dashboard ---"
curl -s --noproxy '*' -u dave:pass-dave-123 -X POST "$B/api/dashboards/db" \
  -H 'Content-Type: application/json' \
  -d '{"dashboard":{"uid":"dave-a","title":"Dave In A","panels":[]},"folderUid":"teama","overwrite":true}' -o /tmp/da -w '  http=%{http_code}\n'
head -c 250 /tmp/da; echo
echo
echo "  --- dave 往 teamb(未授权) 建 dashboard ---"
curl -s --noproxy '*' -u dave:pass-dave-123 -X POST "$B/api/dashboards/db" \
  -H 'Content-Type: application/json' \
  -d '{"dashboard":{"uid":"dave-b","title":"Dave In B","panels":[]},"folderUid":"teamb","overwrite":true}' -o /tmp/db -w '  http=%{http_code}\n'
head -c 250 /tmp/db; echo
