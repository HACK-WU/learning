#!/bin/bash
echo "=== 1. 聚合产物 up:sum_samples（tenant 79）==="
curl -s "http://localhost:8487/select/79/prometheus/api/v1/query?query=up:sum_samples" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d['data']['result']
if not rs: print('  无数据')
for r in rs:
    print('  %-46s = %s' % (str(r['metric'])[:44], r['value'][1]))
" 2>/dev/null

echo
echo "=== 2. 原始 up 是否保留（keep_input 默认 true）==="
curl -s "http://localhost:8487/select/79/prometheus/api/v1/query?query=up" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d['data']['result']
if not rs: print('  无数据')
for r in rs:
    print('  job=%-14s instance=%-22s = %s' % (r['metric'].get('job'), r['metric'].get('instance'), r['value'][1]))
" 2>/dev/null

echo
echo "=== 3. 基数对照 ==="
t79=$(curl -s "http://localhost:8487/select/79/prometheus/api/v1/label/__name__/values" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)['data']))" 2>/dev/null)
t0=$(curl -s "http://localhost:8487/select/0/prometheus/api/v1/label/__name__/values" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)['data']))" 2>/dev/null)
echo "  tenant 79（vmagent + 流式聚合）指标数 = $t79"
echo "  tenant 0 （vmagent 原始全量）  指标数 = $t0"

echo
echo "=== 4. vmagent 所有目标的 up 状态（最终快照）==="
curl -s http://localhost:8429/api/v1/targets 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    print('  %-14s %-24s health=%-5s samples=%s' % (
        t['labels'].get('job'), t['labels'].get('instance'),
        t['health'], t.get('lastSamplesScraped')))
" 2>/dev/null
