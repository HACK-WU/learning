#!/usr/bin/env bash
# 三方查询代价对比（修正 header 传参）
set -uo pipefail
NET=l9net
now=$(date +%s); st=$((now-300))
QQ='app_requests_total'

echo "############ 同一 range 查询在不同方案的结果 ############"
echo "   query=$QQ  range=最近5分钟 step=15s"
echo

# Thanos
echo -n "   Thanos-Q1   "
docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode "query=$QQ" --data-urlencode "start=$st" --data-urlencode "end=$now" \
  --data-urlencode 'step=15s' \
  http://l9-thanos-query:19191/api/v1/query_range 2>/dev/null \
| python3 -c "import sys,json;d=json.load(sys.stdin);rs=d['data']['result'];print('序列=%d 点=%d'%(len(rs),sum(len(r['values']) for r in rs)))"

echo -n "   Thanos-Q2   "
docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode "query=$QQ" --data-urlencode "start=$st" --data-urlencode "end=$now" \
  --data-urlencode 'step=15s' \
  http://l9-thanos-query-nodedup:19191/api/v1/query_range 2>/dev/null \
| python3 -c "import sys,json;d=json.load(sys.stdin);rs=d['data']['result'];print('序列=%d 点=%d'%(len(rs),sum(len(r['values']) for r in rs)))"

# Mimir（header 用变量展开，避免转义空格）
echo -n "   Mimir-A     "
docker run --rm --network $NET curlimages/curl:latest -s -G \
  -H "X-Scope-OrgID: tenantA" \
  --data-urlencode "query=$QQ" --data-urlencode "start=$st" --data-urlencode "end=$now" \
  --data-urlencode 'step=15s' \
  http://l9-mimir:8080/prometheus/api/v1/query_range 2>/dev/null \
| python3 -c "import sys,json;d=json.load(sys.stdin);rs=d['data']['result'];print('序列=%d 点=%d'%(len(rs),sum(len(r['values']) for r in rs)))"

echo -n "   VM-single   "
docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode "query=$QQ" --data-urlencode "start=$st" --data-urlencode "end=$now" \
  --data-urlencode 'step=15s' \
  http://l9-vm-single:8428/prometheus/api/v1/query_range 2>/dev/null \
| python3 -c "import sys,json;d=json.load(sys.stdin);rs=d['data']['result'];print('序列=%d 点=%d'%(len(rs),sum(len(r['values']) for r in rs)))"

echo -n "   VM-cluster  "
docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode "query=$QQ" --data-urlencode "start=$st" --data-urlencode "end=$now" \
  --data-urlencode 'step=15s' \
  http://l9-vmselect:8481/prometheus/api/v1/query_range 2>/dev/null \
| python3 -c "import sys,json;d=json.load(sys.stdin);rs=d['data']['result'];print('序列=%d 点=%d'%(len(rs),sum(len(r['values']) for r in rs)))"

echo
echo "############ 去重对聚合值的影响（决定性）############"
for pair in "Thanos-Q1|http://l9-thanos-query:19191/api/v1/query|" \
            "Thanos-Q2|http://l9-thanos-query-nodedup:19191/api/v1/query|" \
            "Mimir-A|http://l9-mimir:8080/prometheus/api/v1/query|tenantA" \
            "VM-single|http://l9-vm-single:8428/prometheus/api/v1/query|"; do
  n=${pair%%|*}; rest=${pair#*|}; u=${rest%%|*}; t=${rest#*|}
  printf '   %-11s sum(app_requests_total) = ' "$n"
  if [ -n "$t" ]; then
    docker run --rm --network $NET curlimages/curl:latest -s -G \
      -H "X-Scope-OrgID: $t" --data-urlencode 'query=sum(app_requests_total)' "$u" 2>/dev/null
  else
    docker run --rm --network $NET curlimages/curl:latest -s -G \
      --data-urlencode 'query=sum(app_requests_total)' "$u" 2>/dev/null
  fi | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin); rs=d['data']['result']
    print(rs[0]['value'][1] if rs else 'N/A')
except Exception as e: print('ERR')
"
done
