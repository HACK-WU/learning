#!/usr/bin/env bash
set -uo pipefail
NET=l9net
BASE=http://l9-vmselect:8481/select/0/prometheus
now=$(date +%s); st=$((now-300))

echo "=== VM 集群版（正确路径 /select/0/prometheus/...）==="
echo -n "   sum(app_requests_total) = "
docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode 'query=sum(app_requests_total)' \
  "$BASE/api/v1/query" 2>/dev/null \
| python3 -c "
import sys,json
try:
    d=json.load(sys.stdin); rs=d['data']['result']
    print(rs[0]['value'][1] if rs else 'N/A(无数据)')
except Exception as e: print('ERR %s' % e)"

echo -n "   range 查询: "
docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode 'query=app_requests_total' \
  --data-urlencode "start=$st" --data-urlencode "end=$now" \
  --data-urlencode 'step=15s' \
  "$BASE/api/v1/query_range" 2>/dev/null \
| python3 -c "
import sys,json
try:
    d=json.load(sys.stdin); rs=d['data']['result']
    print('%d 序列 / %d 点' % (len(rs), sum(len(r['values']) for r in rs)))
except Exception as e: print('ERR %s' % e)"

echo
echo "=== 对照：单节点 VM 路径（无租户编号）==="
echo -n "   sum = "
docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode 'query=sum(app_requests_total)' \
  "http://l9-vm-single:8428/prometheus/api/v1/query" 2>/dev/null \
| python3 -c "
import sys,json
try:
    d=json.load(sys.stdin); rs=d['data']['result']
    print(rs[0]['value'][1] if rs else 'N/A')
except Exception as e: print('ERR %s' % e)"
