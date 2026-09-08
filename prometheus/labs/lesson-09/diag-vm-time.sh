#!/usr/bin/env bash
set -uo pipefail
NET=l9net

echo "=== 1. VM 时间基准 ==="
now=$(date +%s)
echo "   host now = $now ($(date -u -d @$now +%FT%TZ))"

echo
echo "=== 2. 带时间范围查询（最近 5 分钟）==="
docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode 'query=count(app_requests_total)' \
  --data-urlencode "time=$now" \
  http://l9-vm-single:8428/prometheus/api/v1/query 2>/dev/null | head -c 250
echo

echo
echo "=== 3. range 查询（最近 2 分钟，step=15s）==="
st=$((now-120))
docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode 'query=count(app_requests_total)' \
  --data-urlencode "start=$st" \
  --data-urlencode "end=$now" \
  --data-urlencode 'step=15s' \
  http://l9-vm-single:8428/prometheus/api/v1/query_range 2>/dev/null | head -c 300
echo

echo
echo "=== 4. 不指定时间（默认）与指定时间对比 ==="
echo -n "   默认: "
docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode 'query=app_requests_total' \
  http://l9-vm-single:8428/prometheus/api/v1/query 2>/dev/null \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d['data']['result']),'条')"
echo -n "   指定 now: "
docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode 'query=app_requests_total' \
  --data-urlencode "time=$now" \
  http://l9-vm-single:8428/prometheus/api/v1/query 2>/dev/null \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d['data']['result']),'条')"

echo
echo "=== 5. VM 的 vm_rows_inserted_total 是哪个 type ==="
docker run --rm --network $NET curlimages/curl:latest -s \
  http://l9-vm-single:8428/metrics 2>/dev/null \
  | grep 'vm_rows_inserted_total' | grep -v ' 0$' | head -6
