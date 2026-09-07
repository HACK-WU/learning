#!/usr/bin/env bash
# 课 2 知识点 2.2 实验：access=proxy 与 access=direct 的真实差别
# 课 1 曾标注「access=direct 的 CORS 行为课 2 展开」，本课兑现
set -u
GF="http://localhost:3014"
CK=/tmp/l02ds_ck.txt
PROM_HOST_PORT=9201   # 宿主映射端口，模拟「浏览器视角」可达的地址

curl -s -c $CK -X POST "$GF/login" -H 'Content-Type: application/json' \
  -d '{"user":"admin","password":"lab-pass-2026"}' >/dev/null

echo "=== 0. 清理旧数据源 ==="
for id in $(curl -s -b $CK "$GF/api/datasources" | python3 -c "import sys,json;[print(d['id']) for d in json.load(sys.stdin)]" 2>/dev/null); do
  curl -s -b $CK -X DELETE "$GF/api/datasources/$id" >/dev/null
done
echo "  已清空"

echo
echo "=== 1. 建 proxy 模式数据源（url 用容器名，只有 Grafana 后端能解析）==="
curl -s -b $CK -X POST "$GF/api/datasources" -H 'Content-Type: application/json' \
  -d '{"name":"PROM_PROXY","type":"prometheus","url":"http://grafana-prom:9090","access":"proxy"}' \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print('  创建:',d.get('name'),'uid=',d['datasource'].get('uid'),'access=',d['datasource'].get('access'))" 2>/dev/null

echo
echo "=== 2. 建 direct 模式数据源（url 用宿主地址：浏览器直连）==="
curl -s -b $CK -X POST "$GF/api/datasources" -H 'Content-Type: application/json' \
  -d "{\"name\":\"PROM_DIRECT\",\"type\":\"prometheus\",\"url\":\"http://localhost:${PROM_HOST_PORT}\",\"access\":\"direct\"}" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print('  创建:',d.get('name'),'uid=',d['datasource'].get('uid'),'access=',d['datasource'].get('access'))" 2>/dev/null

echo
echo "=== 3. 用 Grafana 的 /api/ds/query 走后端代理查 proxy 数据源 ==="
PROXY_UID=$(curl -s -b $CK "$GF/api/datasources/name/PROM_PROXY" | python3 -c "import sys,json;print(json.load(sys.stdin)['uid'])" 2>/dev/null)
echo "  uid=$PROXY_UID"
body=$(curl -s -b $CK -X POST "$GF/api/ds/query" -H 'Content-Type: application/json' \
  -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"type\":\"prometheus\",\"uid\":\"$PROXY_UID\"},\"expr\":\"up\",\"instant\":true,\"range\":false}],\"from\":\"now-5m\",\"to\":\"now\"}")
echo "  返回（截断 300 字符）: $(echo "$body" | head -c 300)"
echo
echo "  --- 关键：这条请求发往 grafana 后端，由后端用容器名 grafana-prom 解析 ---"

echo
echo "=== 4. 用 /api/ds/query 查 direct 数据源，看后端怎么处理 ==="
DIR_UID=$(curl -s -b $CK "$GF/api/datasources/name/PROM_DIRECT" | python3 -c "import sys,json;print(json.load(sys.stdin)['uid'])" 2>/dev/null)
echo "  uid=$DIR_UID"
body2=$(curl -s -b $CK -X POST "$GF/api/ds/query" -H 'Content-Type: application/json' \
  -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"type\":\"prometheus\",\"uid\":\"$DIR_UID\"},\"expr\":\"up\",\"instant\":true,\"range\":false}],\"from\":\"now-5m\",\"to\":\"now\"}")
echo "  返回（截断 400 字符）: $(echo "$body2" | head -c 400)"

echo
echo "=== 5. Health check 接口对两种模式的态度 ==="
for n in PROM_PROXY PROM_DIRECT; do
  id=$(curl -s -b $CK "$GF/api/datasources/name/$n" | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])" 2>/dev/null)
  echo -n "  $n (id=$id) /api/datasources/$id/health -> "
  curl -s -b $CK "http://localhost:3014/api/datasources/$id/health" -w ' [HTTP %{http_code}]\n' | head -c 300
  echo
done

echo
echo "=== 6. 数据源的敏感字段是否回显（proxy 才有的意义）==="
curl -s -b $CK "$GF/api/datasources" \
  | python3 -c "
import sys,json
for d in json.load(sys.stdin):
    print(f\"  {d['name']}: access={d['access']} url={d['url']} basicAuth={d.get('basicAuth')} jsonData={d.get('jsonData')} secureJsonFields={d.get('secureJsonFields')}\")
" 2>/dev/null
