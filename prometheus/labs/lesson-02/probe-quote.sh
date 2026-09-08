echo "=== 关键区分：单引号内的 \\\" 是否被 shell 吃掉 ==="
echo "--- A1: 单引号包裹 URL，内部用 \\\" 转义（讲义原写法） ---"
curl -s -w "\nHTTP=%{http_code}\n" 'http://localhost:9097/api/v1/query?query=app_build_info{job=\"metric-relabel-demo\"}'

echo
echo "--- A2: 单引号包裹 URL，内部用裸双引号 ---"
curl -s -w "\nHTTP=%{http_code}\n" 'http://localhost:9097/api/v1/query?query=app_build_info{job="metric-relabel-demo"}' | head -c 200

echo
echo "--- A3: 双引号包裹 URL，内部用 \\\" 转义 ---"
curl -s -w "\nHTTP=%{http_code}\n" "http://localhost:9097/api/v1/query?query=app_build_info{job=\"metric-relabel-demo\"}" | head -c 200

echo
echo "--- A4: -G + --data-urlencode（最稳） ---"
curl -s -G 'http://localhost:9097/api/v1/query' \
  --data-urlencode 'query=app_build_info{job="metric-relabel-demo"}' | head -c 250
