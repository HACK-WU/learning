set +x
PROM=http://localhost:9094

echo "=== 应用侧：当前瞬时错误率 ==="
docker exec l4-app python3 -c "
import urllib.request
print(urllib.request.urlopen('http://localhost:8080/fault/status').read().decode())
"

echo
echo "=== TSDB 侧：采样 60 秒的 ratio1m 实际值（每 5 秒一次） ==="
for i in $(seq 1 12); do
  val=$(curl -s -G "$PROM/api/v1/query" \
    --data-urlencode 'query=job:app_requests_error:ratio1m' \
    | python3 -c "
import json,sys
r = json.load(sys.stdin)['data']['result']
print('%.4f' % float(r[0]['value'][1]) if r else 'n/a')
")
  echo "  t=$((i*5))s  ratio1m=$val"
  sleep 5
done
