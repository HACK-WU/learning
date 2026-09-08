#!/usr/bin/env bash
PORT=19440
echo "############ 实验 4：控制手段的效果与副作用（实测）############"
echo ""
echo "=== 4.1 各 job 抓取健康状态（副作用核心证据）==="
curl -s "http://localhost:$PORT/api/v1/targets?state=active" | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']['activeTargets']
for t in sorted(d,key=lambda x:x['labels']['job']):
    e=t.get('lastError','')
    print(f\"  {t['labels']['job']:20s} health={t['health']:5s} {e}\")
"
echo ""
echo "=== 4.2 各 job 实际入库序列数 ==="
curl -s --data-urlencode 'query=count by (job) ({__name__=~"card_.*"})' \
  "http://localhost:$PORT/api/v1/query" | python3 -c "
import sys,json
d=json.load(sys.stdin)
if d['status']!='success': print('  ERR',d.get('error')); sys.exit()
for x in sorted(d['data']['result'],key=lambda y:y['metric'].get('job','')):
    print(f\"  job={x['metric'].get('job'):20s} 序列数={x['value'][1]}\")
" 2>&1
echo ""
echo "=== 4.3 up 指标（硬失败的直接证据）==="
curl -s --data-urlencode 'query=up' "http://localhost:$PORT/api/v1/query" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for x in sorted(d['data']['result'],key=lambda y:y['metric'].get('job','')):
    print(f\"  up{{job={x['metric'].get('job'):20s}}} = {x['value'][1]}\")
" 2>&1
echo ""
echo "=== 4.4 scrape_samples_scraped（抓到了多少）==="
curl -s --data-urlencode 'query=scrape_samples_scraped' "http://localhost:$PORT/api/v1/query" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for x in sorted(d['data']['result'],key=lambda y:y['metric'].get('job','')):
    print(f\"  job={x['metric'].get('job'):20s} scraped={x['value'][1]}\")
" 2>&1
echo ""
echo "=== 4.5 TSDB 总序列数 ==="
curl -s "http://localhost:$PORT/api/v1/status/tsdb" | python3 -c "
import sys,json;d=json.load(sys.stdin)['data']['headStats']
print(f\"  numSeries={d['numSeries']} numLabelPairs={d['numLabelPairs']}\")"
echo ""
echo "=== 4.6 app-drop 是否真的丢掉了目标指标 ==="
curl -s --data-urlencode 'query=count by (__name__) ({__name__=~"card_bad_by_.*"})' \
  "http://localhost:$PORT/api/v1/query" | python3 -c "
import sys,json
d=json.load(sys.stdin)
if d['status']!='success': print('  ERR'); sys.exit()
for x in d['data']['result']:
    print(f\"  {x['metric'].get('__name__'):24s} 剩余序列={x['value'][1]}\")
" 2>&1
