#!/bin/bash
set -u
echo "########## 下钻验证：从 Loki 里取 trace_id，再回查 Jaeger ##########"
echo

echo "=== 1. 从 Loki 查到的日志里取一个真实的 trace_id ==="
TID=$(curl -s --noproxy '*' -m 10 -G 'http://localhost:3101/loki/api/v1/query_range' --data-urlencode 'query={job="shop"}' --data-urlencode 'limit=5' --data-urlencode "start=$(( $(date +%s) - 300 ))000000000" --data-urlencode "end=$(date +%s)000000000" 2>/dev/null | python3 -c "
import sys,json,re
d=json.load(sys.stdin)
for s in d.get('data',{}).get('result',[]):
    for v in s.get('values',[]):
        m=re.search(r'\"trace_id\": \"([a-f0-9]{32})\"', v[1])
        if m: print(m.group(1)); sys.exit()
" 2>/dev/null)
echo "  Loki 中的 trace_id = $TID"
echo

if [ -z "$TID" ]; then echo "  ❌ 没取到"; exit 1; fi

echo "=== 2. 用它在 Loki 里精确搜索（模拟用户点 trace_id 的行为）==="
curl -s --noproxy '*' -m 10 -G 'http://localhost:3101/loki/api/v1/query_range' --data-urlencode "query={job=\"shop\"} |= \"$TID\"" --data-urlencode 'limit=5' --data-urlencode "start=$(( $(date +%s) - 600 ))000000000" --data-urlencode "end=$(date +%s)000000000" 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)
r=d.get('data',{}).get('result',[])
n=sum(len(s.get('values',[])) for s in r)
print('  命中日志条数 =', n)
for s in r:
    for v in s.get('values',[])[:3]: print('   ', v[1][:130])
" 2>&1
echo

echo "=== 3. 同一个 trace_id 在 Jaeger 里能打开吗（第三跳）==="
curl -s --noproxy '*' -m 10 "http://localhost:16687/api/traces/$TID" 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin).get('data',[])
if not d: print('  ❌ Jaeger 里没有这个 trace'); sys.exit()
t=d[0]
print('  ✅ trace 存在，spans =', len(t['spans']))
for s in t['spans']:
    dur=s.get('duration',0)/1000
    err=[x for x in s.get('tags',[]) if x.get('key')=='error']
    print('     -', s['operationName'], f'{dur:.1f}ms', 'ERROR' if err else '')
    print('       service:', [x['value'] for x in s.get('process',{}).get('tags',[]) if x['key']=='service.name'] or [x['value'] for x in s.get('tags',[]) if x['key']=='service.name'])
" 2>&1
echo

echo "=== 4. 完整链路串起来：接口耗时 vs span 耗时 ==="
curl -s --noproxy '*' -m 10 "http://localhost:16687/api/traces/$TID" 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin).get('data',[])
if not d: sys.exit()
spans=d[0]['spans']
root=[s for s in spans if not s.get('references')]
if root:
    r=root[0]
    print('  根 span:', r['operationName'], f\"{r['duration']/1000:.1f}ms\")
print('  子 span 数:', len(spans)-len(root))
" 2>&1
