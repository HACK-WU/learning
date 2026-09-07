#!/bin/bash
B=http://localhost:3002
U='-u admin:admin'
J='python3 -m json.tool'

echo "=== 1. 建第二个 Org ==="
curl -s --noproxy '*' $U -X POST $B/api/orgs \
  -H 'Content-Type: application/json' -d '{"name":"TeamB"}' | $J
echo

echo "=== 2. 列所有 Org ==="
curl -s --noproxy '*' $U $B/api/orgs | $J
echo

echo "=== 3. 建两个普通用户 ==="
for u in alice bob; do
  echo "--- $u ---"
  curl -s --noproxy '*' $U -X POST $B/api/admin/users \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"$u\",\"login\":\"$u\",\"email\":\"$u@example.com\",\"password\":\"pass-$u-123\"}" | $J
done
echo

echo "=== 4. 列用户 ==="
curl -s --noproxy '*' $U $B/api/org/users | $J
echo

echo "=== 5. 建 Team ==="
curl -s --noproxy '*' $U -X POST $B/api/teams \
  -H 'Content-Type: application/json' -d '{"name":"OpsTeam","email":"ops@example.com"}' | $J
echo

echo "=== 6. 列 Team ==="
curl -s --noproxy '*' $U $B/api/teams?perpage=50 | $J
