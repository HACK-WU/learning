#!/usr/bin/env bash
# CORS 复测：上一轮 A 组三项全是 401，原因是漏带 -b $CK（脚本缺陷，非 CORS 结论）
# 本轮补齐 cookie 后重测
set -u
GF="http://localhost:3014"
CK=/tmp/l02cors2_ck.txt

curl -s -c $CK -X POST "$GF/login" -H 'Content-Type: application/json' \
  -d '{"user":"admin","password":"lab-pass-2026"}' >/dev/null

DIR_UID=$(curl -s -b $CK "$GF/api/datasources/name/PROM_DIRECT" | python3 -c "import sys,json;print(json.load(sys.stdin)['uid'])" 2>/dev/null)
PROXY_UID=$(curl -s -b $CK "$GF/api/datasources/name/PROM_PROXY" | python3 -c "import sys,json;print(json.load(sys.stdin)['uid'])" 2>/dev/null)
echo "PROM_DIRECT uid=$DIR_UID"
echo "PROM_PROXY  uid=$PROXY_UID"
echo

echo "=== A. 带 cookie + 带外站 Origin，看 Grafana 是否回 CORS 头 ==="
echo "  A1 实际 POST（Origin: http://evil.example.com）:"
curl -s -b $CK -D /tmp/c1.txt -o /dev/null -X POST "$GF/api/ds/query" \
  -H 'Origin: http://evil.example.com' -H 'Content-Type: application/json' \
  -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"type\":\"prometheus\",\"uid\":\"$PROXY_UID\"},\"expr\":\"up\",\"instant\":true}],\"from\":\"now-5m\",\"to\":\"now\"}"
grep -iE '^(HTTP/|access-control|vary)' /tmp/c1.txt || echo "     （无 CORS 相关头）"

echo
echo "  A2 OPTIONS 预检:"
curl -s -b $CK -D /tmp/c2.txt -o /dev/null -X OPTIONS "$GF/api/ds/query" \
  -H 'Origin: http://evil.example.com' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: content-type'
grep -iE '^(HTTP/|access-control|allow)' /tmp/c2.txt || echo "     （无 CORS 相关头）"

echo
echo "  A3 不带 Origin 的基线（对比用）:"
curl -s -b $CK -D /tmp/c3.txt -o /dev/null -X POST "$GF/api/ds/query" \
  -H 'Content-Type: application/json' \
  -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"type\":\"prometheus\",\"uid\":\"$PROXY_UID\"},\"expr\":\"up\",\"instant\":true}],\"from\":\"now-5m\",\"to\":\"now\"}"
grep -iE '^(HTTP/|access-control)' /tmp/c3.txt || echo "     （无 CORS 相关头）"

echo
echo "=== B. 直接对 Prometheus 自身的 CORS 做对照（后端视角）==="
echo "  B1 从宿主问 Prometheus（9201）:"
curl -s -D /tmp/p1.txt -o /dev/null -H 'Origin: http://evil.example.com' \
  "http://localhost:9201/api/v1/query?query=up"
grep -iE '^(HTTP/|access-control)' /tmp/p1.txt || echo "     （无 CORS 相关头）"

echo
echo "  B2 从 Grafana 容器内问 Prometheus（模拟 Grafana 后端视角）:"
docker exec gf-l02d sh -c "wget -q -O /dev/null -S 'http://grafana-prom:9090/api/v1/query?query=up' 2>&1 | grep -i 'access-control'" 2>/dev/null \
  || docker exec gf-l02d sh -c "apk add curl >/dev/null 2>&1; curl -s -D - -o /dev/null -H 'Origin: http://evil.example.com' 'http://grafana-prom:9090/api/v1/query?query=up' 2>/dev/null | grep -iE '^(HTTP/|access-control)'" 2>/dev/null \
  || echo "     （容器内无 curl/wget，跳过）"

echo
echo "=== C. 结论用证据：direct 的报错文本里，发起方是谁 ==="
curl -s -b $CK -X POST "$GF/api/ds/query" -H 'Content-Type: application/json' \
  -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"type\":\"prometheus\",\"uid\":\"$DIR_UID\"},\"expr\":\"up\",\"instant\":true}],\"from\":\"now-5m\",\"to\":\"now\"}" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
r=d.get('results',{}).get('A',{})
print('  error      :', r.get('error'))
print('  errorSource:', r.get('errorSource'))
print('  status     :', r.get('status'))
" 2>/dev/null
