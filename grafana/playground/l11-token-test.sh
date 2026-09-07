#!/bin/bash
B=http://localhost:3002
TOK='glsa_<YOUR_TOKEN_HERE>'
A="Authorization: Bearer $TOK"

echo "=== 1. 服务账号 token 能读 dashboard 吗 ==="
curl -s --noproxy '*' -H "$A" "$B/api/dashboards/uid/prov-dash-001" -o /tmp/s1 -w '  http=%{http_code}\n'
head -c 200 /tmp/s1; echo
echo

echo "=== 2. 服务账号 token 能读数据源吗 ==="
curl -s --noproxy '*' -H "$A" "$B/api/datasources" -o /tmp/s2 -w '  http=%{http_code}\n'
head -c 200 /tmp/s2; echo
echo

echo "=== 3. 服务账号(Viewer) 能建 dashboard 吗（应 403）==="
curl -s --noproxy '*' -H "$A" -X POST "$B/api/dashboards/db" \
  -H 'Content-Type: application/json' \
  -d '{"dashboard":{"uid":"sa-dash","title":"SA Dash","panels":[]},"overwrite":false}' -o /tmp/s3 -w '  http=%{http_code}\n'
head -c 250 /tmp/s3; echo
echo

echo "=== 4. 服务账号能管理自己（改权限）吗 ==="
curl -s --noproxy '*' -H "$A" "$B/api/org/users" -o /tmp/s4 -w '  http=%{http_code}\n'
head -c 250 /tmp/s4; echo
echo

echo "=== 5. 坐实 API Key 是否被移除：查 Grafana 二进制/日志 ==="
echo "  --- 尝试创建（POST）---"
curl -s --noproxy '*' -u admin:admin -X POST "$B/api/auth/keys" \
  -H 'Content-Type: application/json' -d '{"name":"k1","role":"Viewer"}' -o /tmp/a1 -w '  POST /api/auth/keys http=%{http_code}\n'
head -c 200 /tmp/a1; echo
echo "  --- 容器内是否有 apikeys 表 ---"
docker exec grafana-prov sh -c "ls /var/lib/grafana/ 2>/dev/null" || echo "  (无法列目录)"
echo "  --- 前端是否还有 API Key 菜单（查 API 路由）---"
curl -s --noproxy '*' -u admin:admin "$B/api/frontend/settings" 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    for k in ['apiKeysEnabled','serviceAccountsEnabled']:
        print('   %s = %s' % (k,d.get(k)))
except Exception as e: print('   ERR',e)
"
