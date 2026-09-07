#!/bin/bash
B=http://localhost:3002
U='-u admin:admin'
J='python3 -m json.tool'

echo "=== 1. 建 TeamB 组用户 carol（属于 B 团队）==="
curl -s --noproxy '*' $U -X POST "$B/api/admin/users" \
  -H 'Content-Type: application/json' \
  -d '{"name":"carol","login":"carol","email":"carol@example.com","password":"pass-carol-123"}' | $J
echo

echo "=== 2. 建两个文件夹 ==="
for f in "TeamA-Folder:teama" "TeamB-Folder:teamb"; do
  title="${f%%:*}"; uid="${f##*:}"
  echo "--- $title ($uid) ---"
  curl -s --noproxy '*' $U -X POST "$B/api/folders" \
    -H 'Content-Type: application/json' -d "{\"title\":\"$title\",\"uid\":\"$uid\"}" | $J
done
echo

echo "=== 3. 建第二个 Team (TeamB-Group) ==="
curl -s --noproxy '*' $U -X POST "$B/api/teams" \
  -H 'Content-Type: application/json' -d '{"name":"TeamBGroup","email":"teamb@example.com"}' | $J
echo

echo "=== 4. 列 teams ==="
curl -s --noproxy '*' $U "$B/api/teams/search?perpage=50" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for t in d['teams']: print('  id=%s uid=%s name=%s members=%s' % (t['id'],t['uid'],t['name'],t['memberCount']))
"
echo

echo "=== 5. 把 carol(4?) 加进 TeamBGroup(2) ==="
echo "  carol userId:"
curl -s --noproxy '*' $U "$B/api/users?loginOrEmail=carol" | python3 -c "
import sys,json;d=json.load(sys.stdin);print('   id=',d.get('id'),'uid=',d.get('uid'))
"
