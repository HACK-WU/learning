#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus/labs/lesson-10
NET=l10net; PORT=19440
PASS=0; FAIL=0
ck(){ if [ "$2" = "$3" ]; then echo "PASS  $1"; PASS=$((PASS+1)); else echo "FAIL  $1 (expect=$3 actual=$2)"; FAIL=$((FAIL+1)); fi; }

echo "=== 切回单 job (base) 配置 ==="
docker rm -f l10-prom >/dev/null 2>&1
docker run -d -p $PORT:9090 \
  -v $D/prometheus-base.yml:/etc/prometheus/prometheus.yml:ro \
  --name tmp-prom prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus --web.enable-lifecycle --web.enable-admin-api >/dev/null 2>&1
docker rename tmp-prom l10-prom >/dev/null 2>&1
docker network connect $NET l10-prom >/dev/null 2>&1
for i in $(seq 1 30); do curl -sf "http://localhost:$PORT/-/ready" >/dev/null 2>&1 && break; sleep 1; done
sleep 22

echo ""
echo "--- 前置检查: job 数量应为 1 ---"
NJOB=$(curl -s "localhost:$PORT/api/v1/query?query=up" | python3 -c "
import sys,json;print(len(json.load(sys.stdin)['data']['result']))")
echo "  job 数量 = $NJOB"
ck "单 job 配置" "$NJOB" "1"

echo ""
echo "--- 实验 3: histogram bucket 应为 36 ---"
OUT=$(curl -s --data-urlencode 'query=count by (__name__)({__name__=~"card_hist.*"})' \
  localhost:$PORT/api/v1/query | python3 -c "
import sys,json
for x in json.load(sys.stdin)['data']['result']:
    print(x['metric'].get('__name__'),'=',x['value'][1])")
echo "$OUT"
ck "card_hist_seconds_bucket = 36" "$(echo "$OUT" | grep -c 'card_hist_seconds_bucket = 36')" "1"

echo ""
echo "--- 实验 2: TSDB 状态 API ---"
TS=$(curl -s localhost:$PORT/api/v1/status/tsdb | python3 -c "
import sys,json;d=json.load(sys.stdin)['data']
print('numSeries =',d['headStats']['numSeries'])
[print(f\"  {x['name']} = {x['value']}\") for x in d['seriesCountByMetricName'][:5]]")
echo "$TS"

echo ""
echo "--- 实验 2b: 自身 tsdb 指标应为 NONE ---"
OUT2=$(curl -s localhost:$PORT/api/v1/label/__name__/values \
  | python3 -c "import sys,json;print([m for m in json.load(sys.stdin)['data'] if 'tsdb' in m] or 'NONE')")
echo "  $OUT2"
ck "自身 tsdb 指标 NONE" "$OUT2" "NONE"

echo ""
echo "=============================="
echo "PASS=$PASS  FAIL=$FAIL"
