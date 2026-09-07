#!/bin/bash
B=http://localhost:3002
U='-u admin:admin'
J='python3 -m json.tool'

echo "=== 1. alice 当前在哪些 Org ==="
curl -s --noproxy '*' $U "$B/api/users/2/orgs" | $J
echo

echo "=== 2. 把 alice 加入 Org 2 (TeamB) ==="
curl -s --noproxy '*' $U -X POST "$B/api/orgs/2/users" \
  -H 'Content-Type: application/json' -d '{"loginOrEmail":"alice","role":"Viewer"}' | $J
echo

echo "=== 3. 再看 alice 的 Org ==="
curl -s --noproxy '*' $U "$B/api/users/2/orgs" | $J
echo

echo "=== 4. Org 1 的 dashboard（admin 视角）==="
curl -s --noproxy '*' $U "$B/api/search?type=dash-db" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  count=',len(d))
for x in d: print('   ',x.get('uid'),x.get('title'),'folder=',x.get('folderTitle'))
"
echo

echo "=== 5. alice 以 Org 1 身份看 dashboard ==="
curl -s --noproxy '*' -u alice:pass-alice-123 "$B/api/search?type=dash-db" -o /tmp/a1 -w '  http=%{http_code}\n'
head -c 400 /tmp/a1; echo
echo

echo "=== 6. alice 切到 Org 2 后看 dashboard ==="
# 切换组织：POST /api/user/using/{orgId}
curl -s --noproxy '*' -u alice:pass-alice-123 -X POST "$B/api/user/using/2" -o /tmp/sw -w '  switch http=%{http_code}\n'
head -c 200 /tmp/sw; echo
curl -s --noproxy '*' -u alice:pass-alice-123 "$B/api/search?type=dash-db" -o /tmp/a2 -w '  http=%{http_code}\n'
head -c 400 /tmp/a2; echo
echo

echo "=== 7. alice 在 Org2 看数据源 ==="
curl -s --noproxy '*' -u alice:pass-alice-123 "$B/api/datasources" -o /tmp/a3 -w '  http=%{http_code}\n'
head -c 400 /tmp/a3; echo
