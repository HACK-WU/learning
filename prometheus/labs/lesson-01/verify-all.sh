set -x

echo "########## 步骤 7 修正后：推送 ##########"
NOW=$(date +%s)
printf '# TYPE batch_last_run_timestamp_seconds gauge\nbatch_last_run_timestamp_seconds %s\n' "$NOW" \
  | docker exec -i prometheus wget -qO- --post-file=- \
      'http://pushgateway:9091/metrics/job/nightly-batch/instance/batch-01'
echo "push exit=$?"

sleep 10
curl -s 'http://localhost:9095/api/v1/query?query=batch_last_run_timestamp_seconds' \
  | python3 -c "import json,sys; [print(r['metric'], '->', r['value'][1]) for r in json.load(sys.stdin)['data']['result']]"

echo "########## 步骤 3：看第一条数据 ##########"
curl -s 'http://localhost:9095/api/v1/query?query=demo_http_requests_total' \
  | python3 -c "import json,sys; [print(r['metric'], '->', r['value'][1]) for r in json.load(sys.stdin)['data']['result']]"

echo "########## 步骤 4：产生流量 ##########"
for i in $(seq 1 20); do
  docker exec prometheus wget -qO- http://demo-app:8080/order
done
sleep 12
curl -s 'http://localhost:9095/api/v1/query?query=demo_http_requests_total' \
  | python3 -c "import json,sys; [print(r['metric']['endpoint'], '->', r['value'][1]) for r in json.load(sys.stdin)['data']['result']]"

echo "########## 步骤 5：元指标 ##########"
curl -s 'http://localhost:9095/api/v1/query?query=scrape_duration_seconds' \
  | python3 -c "import json,sys; [print(f\"{r['metric']['job']:12s} {r['metric']['instance']:24s} {r['value'][1]}\") for r in json.load(sys.stdin)['data']['result']]"

echo "########## 知识点 1 示例：head_series ##########"
curl -s 'http://localhost:9095/api/v1/query?query=prometheus_tsdb_head_series' \
  | python3 -m json.tool | grep -E '"value"'

echo "########## 清理 ##########"
docker exec demo-app python3 -c "
import urllib.request
r = urllib.request.Request('http://pushgateway:9091/metrics/job/nightly-batch/instance/batch-01', method='DELETE')
print('HTTP', urllib.request.urlopen(r, timeout=10).status)"
