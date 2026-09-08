echo "=== 根因验证：问题在花括号，不在引号 ==="
echo "--- B1: 花括号编码 %7B%7D，保留双引号 ---"
curl -s -w "\nHTTP=%{http_code}\n" 'http://localhost:9097/api/v1/query?query=app_build_info%7Bjob="metric-relabel-demo"%7D' | head -c 250

echo
echo "--- B2: -G + --data-urlencode（自动编码，最稳） ---"
curl -s -w "\nHTTP=%{http_code}\n" -G 'http://localhost:9097/api/v1/query' \
  --data-urlencode 'query=app_build_info{job="metric-relabel-demo"}' | head -c 250

echo
echo "--- B3: 不带花括号的查询（对照组） ---"
curl -s -w "\nHTTP=%{http_code}\n" 'http://localhost:9097/api/v1/query?query=up' | head -c 150
