#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus/labs/lesson-10
NET=l10net; PORT=19440
PASS=0; FAIL=0
ck(){ if [ "$2" = "$3" ]; then echo "PASS  $1"; PASS=$((PASS+1)); else echo "FAIL  $1 (expect=$3 actual=$2)"; FAIL=$((FAIL+1)); fi; }

echo "===== 逐字执行讲义第四幕命令 ====="

echo ""
echo "--- 实验 2 命令 1: TSDB 状态 API ---"
OUT=$(curl -s localhost:$PORT/api/v1/status/tsdb \
  | python3 -c "import sys,json;d=json.load(sys.stdin)['data'];\
print(d['headStats']); \
[print(x) for x in d['seriesCountByMetricName'][:5]]" 2>&1)
echo "$OUT" | head -6
ck "TSDB API 可返回 numSeries" "$(echo "$OUT" | grep -c numSeries)" "1"

echo ""
echo "--- 实验 2 命令 2: 自身指标检查（讲义称应为 NONE）---"
OUT2=$(curl -s localhost:$PORT/api/v1/label/__name__/values \
  | python3 -c "import sys,json;print([m for m in json.load(sys.stdin)['data'] if 'tsdb' in m] or 'NONE')" 2>&1)
echo "  输出: $OUT2"
ck "自身 tsdb 指标为 NONE（与讲义一致）" "$OUT2" "NONE"

echo ""
echo "--- 实验 3 命令: histogram 桶数 ---"
OUT3=$(curl -s --data-urlencode 'query=count by (__name__)({__name__=~"card_hist.*"})' \
  localhost:$PORT/api/v1/query 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)
for x in d['data']['result']: print(x['metric'].get('__name__'),'=',x['value'][1])
" 2>&1)
echo "$OUT3"
ck "histogram bucket = 36" "$(echo "$OUT3" | grep -c 'card_hist_seconds_bucket = 36')" "1"

echo ""
echo "--- 实验 4 命令: 四种控制手段健康状态 ---"
OUT4=$(curl -s localhost:$PORT/api/v1/targets?state=active \
  | python3 -c "import sys,json;\
[print(t['labels']['job'], t['health'], t.get('lastError','')) \
 for t in json.load(sys.stdin)['data']['activeTargets']]" 2>&1)
echo "$OUT4"
ck "app-sample-limit 为 down" "$(echo "$OUT4" | grep -c 'app-sample-limit down')" "1"
ck "app-drop 为 up"          "$(echo "$OUT4" | grep -c 'app-drop up')" "1"
ck "app-raw 为 up"           "$(echo "$OUT4" | grep -c 'app-raw up')" "1"
ck "app-label-limit 为 down" "$(echo "$OUT4" | grep -c 'app-label-limit down')" "1"

echo ""
echo "=============================="
echo "PASS=$PASS  FAIL=$FAIL"
