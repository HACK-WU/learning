#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-10
NET=l10net; PORT=19440

q() { curl -s --data-urlencode "query=$1" http://localhost:$PORT/api/v1/query \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
if d['status']!='success': print('ERR',d.get('error')); sys.exit()
r=d['data']['result']
if not r: print('(empty)')
for x in r:
    m=x['metric']; v=x['value'][1] if 'value' in x else x.get('values')
    lab=','.join(f\"{k}={vv}\" for k,vv in m.items() if k!='__name__')
    print(f\"  {m.get('__name__','?')}{'{'+lab+'}' if lab else ''} = {v}\")
"; }

echo "############ 实验 3：诊断高基数（知识点 2）############"
echo ""
echo "=== 3.1 topk 找出序列最多的指标（PromQL 方式）==="
echo "topk(5, count by (__name__)({__name__=~\".+\"}))"
q 'topk(5, count by (__name__)({__name__=~".+"}))'
echo ""
echo "=== 3.2 TSDB 状态 API（更可靠，不依赖自身指标）==="
echo "curl -s localhost:19440/api/v1/status/tsdb"
curl -s "http://localhost:$PORT/api/v1/status/tsdb" | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']
h=d['headStats']
print(f\"  numSeries     = {h['numSeries']}\")
print(f\"  numLabelPairs = {h['numLabelPairs']}\")
print(f\"  chunkCount    = {h['chunkCount']}\")
print('  seriesCountByMetricName (top5):')
for x in d['seriesCountByMetricName'][:5]:
    print(f\"    {x['name']:32s} {x['value']}\")
"
echo ""
echo "=== 3.3 逐标签定位：哪个标签在涨 ==="
echo "count by (user_id) 基数（取前 3 分布）"
curl -s "http://localhost:$PORT/api/v1/series?match[]=card_bad_by_user" 2>/dev/null \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
if d['status']=='success':
    print(f'  card_bad_by_user 序列数 = {len(d[\"data\"])}')
    for s in d['data'][:3]: print('   ',s)
else: print('  ERR',d.get('error'))
"
echo ""
echo "=== 3.4 直方图桶的放大效应 ==="
q 'count(card_hist_seconds_bucket)'
echo "  (说明：一个 histogram 指标按 le 桶展开)"
echo ""
echo "=== 3.5 各指标序列数总览 ==="
q 'count by (__name__)({__name__=~"card_.*"})'
