set -x

echo "=== 验证讲义步骤 7 的推送命令（原样照抄） ==="
NOW=$(date +%s)
printf '# TYPE batch_last_run_timestamp_seconds gauge\nbatch_last_run_timestamp_seconds %s\n' "$NOW" \
  | docker exec -i prometheus wget -qO- --post-data - \
      'http://pushgateway:9091/metrics/job/nightly-batch/instance/batch-01'
echo "push exit=$?"

sleep 10
curl -s 'http://localhost:9095/api/v1/query?query=batch_last_run_timestamp_seconds' \
  | python3 -c "import json,sys; [print(r['metric'], '->', r['value'][1]) for r in json.load(sys.stdin)['data']['result']]"

echo "=== 验证 DELETE 命令（原样照抄） ==="
docker exec demo-app python3 -c "
import urllib.request
r = urllib.request.Request('http://pushgateway:9091/metrics/job/nightly-batch/instance/batch-01', method='DELETE')
print('HTTP', urllib.request.urlopen(r, timeout=10).status)"

sleep 10
curl -s 'http://localhost:9095/api/v1/query?query=batch_last_run_timestamp_seconds' \
  | python3 -c "import json,sys; d=json.load(sys.stdin)['data']['result']; print(d if d else '(空)')"
