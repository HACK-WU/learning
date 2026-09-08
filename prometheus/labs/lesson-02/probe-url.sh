echo "=== A) 原写法：未编码的花括号+引号 ==="
curl -s -w "\nHTTP=%{http_code}\n" 'http://localhost:9097/api/v1/query?query=app_debug_user_id{job="metric-relabel-demo"}' | head -c 300

echo
echo "=== B) 用 --data-urlencode + -G（推荐写法） ==="
curl -s -G 'http://localhost:9097/api/v1/query' \
  --data-urlencode 'query=app_debug_user_id{job="metric-relabel-demo"}' \
  | head -c 300

echo
echo "=== C) 花括号编码，保留引号 ==="
curl -s -G 'http://localhost:9097/api/v1/query' \
  --data-urlencode 'query=app_debug_user_id' | head -c 200
