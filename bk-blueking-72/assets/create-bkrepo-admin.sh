#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 解码 platform 认证串 ====="
DEC=$(echo 'MThiNjFjOWMtOTAxYi00ZWEzLTg5YzMtMWY3NGJlOTQ0YjY2OlVzOFpHRFhQcWs4NmN3TXVrWUFCUXFDWkxBa00zSw==' | base64 -d)
echo "  解码: $DEC"
AK=$(echo "$DEC" | cut -d: -f1)
SK=$(echo "$DEC" | cut -d: -f2)
echo "  accessKey = $AK"
echo "  secretKey = ${SK:0:4}***"

echo ""
echo "===== 2. 用 platform 认证调 auth 建 admin 用户 ====="
AS=10.96.211.56
kubectl exec netprobe -n $NS -- bash -c "
AUTH='Platform MThiNjFjOWMtOTAxYi00ZWEzLTg5YzMtMWY3NGJlOTQ0YjY2OlVzOFpHRFhQcWs4NmN3TXVrWUFCUXFDWkxBa00zSw=='
echo '  --- 尝试 create (userId/name/pwd) ---'
curl -s --max-time 10 -X POST 'http://$AS/service/user/create' \
  -H \"Authorization: \$AUTH\" -H 'Content-Type: application/json' \
  -d '{\"userId\":\"admin\",\"name\":\"admin\",\"pwd\":\"blueking\",\"admin\":true,\"locked\":false}' | head -c 400
echo ''
echo '  --- 尝试 create (变体: 无 admin 字段) ---'
curl -s --max-time 10 -X POST 'http://$AS/service/user/create' \
  -H \"Authorization: \$AUTH\" -H 'Content-Type: application/json' \
  -d '{\"userId\":\"admin\",\"name\":\"admin\",\"pwd\":\"blueking\"}' | head -c 400
echo ''
echo '  --- 查用户详情 ---'
curl -s --max-time 10 -X GET 'http://$AS/service/user/admin' -H \"Authorization: \$AUTH\" | head -c 400
echo ''
" 2>&1

echo ""
echo "===== 3. 验证：mongodb 里 user 集合是否有数据了 ====="
kubectl exec bk-mongodb-0 -n $NS -- bash -c "mongo --quiet -u root -p blueking --authenticationDatabase admin --eval 'print(\"user count=\"+db.getSiblingDB(\"bkrepo\").user.count()); print(\"role count=\"+db.getSiblingDB(\"bkrepo\").role.count());'" 2>&1 | sed 's/^/  /'
