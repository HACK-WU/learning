#!/bin/bash
B=http://localhost:3002
U='-u admin:admin'
SA=6

echo "=== 1. 列服务账号（原始响应）==="
curl -s --noproxy '*' $U "$B/api/serviceaccounts?perpage=50" | head -c 800; echo
echo

echo "=== 2. 用正确 id ($SA) 建 token ==="
curl -s --noproxy '*' $U -X POST "$B/api/serviceaccounts/$SA/tokens" \
  -H 'Content-Type: application/json' -d '{"name":"ci-token-1"}' | python3 -m json.tool
echo

echo "=== 3. 列 token ==="
curl -s --noproxy '*' $U "$B/api/serviceaccounts/$SA/tokens" | python3 -m json.tool
echo

echo "=== 4. API Key 相关接口探测 ==="
for p in /api/auth/keys /api/apikeys /api/org/apikeys; do
  printf "  GET %-20s " "$p"
  curl -s --noproxy '*' $U "$B$p" -o /tmp/k -w 'http=%{http_code} ' 
  head -c 120 /tmp/k; echo
done
echo

echo "=== 5. 用 token 访问 API（验证服务账号能用）==="
TOKEN=$(curl -s --noproxy '*' $U "$B/api/serviceaccounts/$SA/tokens" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d[0].get('key','') if d and isinstance(d,list) and len(d)>0 else '')
")
echo "  token 前缀: ${TOKEN:0:12}..."
if [ -n "$TOKEN" ]; then
  curl -s --noproxy '*' -H "Authorization: Bearer $TOKEN" "$B/api/dashboards/uid/prov-dash-001" -o /tmp/tk -w '  读 dashboard http=%{http_code}\n'
  head -c 150 /tmp/tk; echo
  curl -s --noproxy '*' -H "Authorization: Bearer $TOKEN" "$B/api/datasources" -o /tmp/tk2 -w '  读数据源   http=%{http_code}\n'
  head -c 150 /tmp/tk2; echo
else
  echo "  无 token，跳过"
fi
