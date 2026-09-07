#!/usr/bin/env bash
# 课 2 知识点 2.2 补充实验：
#   A) direct 模式的 CORS 行为（课 1 遗留未实测项，本课兑现）
#   B) /api/datasources/uid/:uid/health 的正确用法（上一轮 id 用法 404）
set -u
GF="http://localhost:3014"
CK=/tmp/l02cors_ck.txt

curl -s -c $CK -X POST "$GF/login" -H 'Content-Type: application/json' \
  -d '{"user":"admin","password":"lab-pass-2026"}' >/dev/null

echo "########## A. direct 模式的 CORS 预检 ##########"
DIR_UID=$(curl -s -b $CK "$GF/api/datasources/name/PROM_DIRECT" | python3 -c "import sys,json;print(json.load(sys.stdin)['uid'])" 2>/dev/null)
echo "  PROM_DIRECT uid=$DIR_UID"
echo
echo "  A1 不带 Origin 的请求（等同 curl / 服务端调用）:"
curl -s -D /tmp/h1.txt -o /dev/null -X POST "$GF/api/ds/query" -H 'Content-Type: application/json' \
  -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"type\":\"prometheus\",\"uid\":\"$DIR_UID\"},\"expr\":\"up\",\"instant\":true}],\"from\":\"now-5m\",\"to\":\"now\"}"
grep -iE '^(HTTP|access-control)' /tmp/h1.txt || echo "     （无 CORS 头）"

echo
echo "  A2 带 Origin 的 OPTIONS 预检（模拟浏览器跨域）:"
curl -s -D /tmp/h2.txt -o /dev/null -X OPTIONS "$GF/api/ds/query" \
  -H 'Origin: http://evil.example.com' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: content-type'
grep -iE '^(HTTP|access-control)' /tmp/h2.txt || echo "     （无 CORS 头）"

echo
echo "  A3 带 Origin 的实际 POST 请求:"
curl -s -D /tmp/h3.txt -o /dev/null -X POST "$GF/api/ds/query" \
  -H 'Origin: http://evil.example.com' -H 'Content-Type: application/json' \
  -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"type\":\"prometheus\",\"uid\":\"$DIR_UID\"},\"expr\":\"up\",\"instant\":true}],\"from\":\"now-5m\",\"to\":\"now\"}"
grep -iE '^(HTTP|access-control)' /tmp/h3.txt || echo "     （无 CORS 头）"

echo
echo "  A4 direct 模式下，后端是否把请求转发给浏览器（查响应头有无 upstream 提示）:"
echo "     上一步 A(direct) 报的是 'Post http://localhost:9201 ... connection refused'"
echo "     → 说明 direct 模式下 Grafana 后端『仍然自己发起了 HTTP 请求』，只是没走代理封装"

echo
echo "########## B. 正确的 health check 端点 ##########"
for n in PROM_PROXY PROM_DIRECT; do
  uid=$(curl -s -b $CK "$GF/api/datasources/name/$n" | python3 -c "import sys,json;print(json.load(sys.stdin)['uid'])" 2>/dev/null)
  echo -n "  B1 GET  /api/datasources/uid/$uid/health -> "
  curl -s -b $CK "$GF/api/datasources/uid/$uid/health" -w ' [HTTP %{http_code}]\n' | head -c 300
  echo
done
echo
echo "  注意：Grafana 的 health check 是『前端』概念——"
echo "  它由浏览器发往 /api/datasources/uid/:uid/health，服务端校验数据源能否连通。"
echo "  UI 上的 Save & test 按钮对应的就是它。"

echo
echo "########## C. Save & test 到底测了什么（用 proxy 数据源看成功/失败两种）##########"
PROXY_UID=$(curl -s -b $CK "$GF/api/datasources/name/PROM_PROXY" | python3 -c "import sys,json;print(json.load(sys.stdin)['uid'])" 2>/dev/null)
echo -n "  C1 正常的 proxy 数据源 health -> "
curl -s -b $CK "$GF/api/datasources/uid/$PROXY_UID/health" -w ' [HTTP %{http_code}]\n' | head -c 300
echo
echo -n "  C2 故意建一个指向不存在端口的数据源，再看 health -> "
BAD=$(curl -s -b $CK -X POST "$GF/api/datasources" -H 'Content-Type: application/json' \
  -d '{"name":"PROM_BROKEN","type":"prometheus","url":"http://grafana-prom:9999","access":"proxy"}')
BAD_UID=$(echo "$BAD" | python3 -c "import sys,json;print(json.load(sys.stdin)['datasource']['uid'])" 2>/dev/null)
echo "     uid=$BAD_UID"
curl -s -b $CK "$GF/api/datasources/uid/$BAD_UID/health" -w ' [HTTP %{http_code}]\n' | head -c 400
echo
echo
echo "  C3 对比：坏数据源上的普通查询返回什么（这是课 4 知识点 4.3 的伏笔）"
curl -s -b $CK -X POST "$GF/api/ds/query" -H 'Content-Type: application/json' \
  -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"type\":\"prometheus\",\"uid\":\"$BAD_UID\"},\"expr\":\"up\",\"instant\":true}],\"from\":\"now-5m\",\"to\":\"now\"}" \
  -w '\n     [外层 HTTP %{http_code}]\n' | head -c 500
