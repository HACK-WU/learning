#!/bin/bash
set -u
echo "########## 为什么日志里的 trace_id 在 Jaeger 查不到 ##########"
echo

TID=$(curl -s --noproxy '*' -m 10 -G 'http://localhost:3101/loki/api/v1/query_range' --data-urlencode 'query={job="shop"}' --data-urlencode 'limit=5' --data-urlencode "start=$(( $(date +%s) - 300 ))000000000" --data-urlencode "end=$(date +%s)000000000" 2>/dev/null | python3 -c "
import sys,json,re
d=json.load(sys.stdin)
for s in d.get('data',{}).get('result',[]):
    for v in s.get('values',[]):
        m=re.search(r'\"trace_id\": \"([a-f0-9]{32})\"', v[1])
        if m: print(m.group(1)); sys.exit()
" 2>/dev/null)
echo "  trace_id = $TID  (32 位十六进制，长度 $(echo -n $TID | wc -c))"
echo

echo "=== 1. Jaeger 里的 traceID 是什么格式？取几条对比 ==="
curl -s --noproxy '*' -m 10 -G 'http://localhost:16687/api/traces' --data-urlencode 'service=shop-api' --data-urlencode 'limit=3' 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin).get('data',[])
print('  Jaeger 返回 trace 数 =', len(d))
for t in d[:3]:
    tid=t['traceID']
    print('   ', tid, '长度=', len(tid))
" 2>&1
echo

echo "=== 2. 关键怀疑：长度不一致（16位 vs 32位）==="
echo "  Jaeger 老版本用 16 位 traceID，OTel 用 32 位。"
echo "  日志里写的是 32 位 format_trace_id，Jaeger 存的如果是 16 位就对不上。"
echo

echo "=== 3. 直接查 Jaeger：用日志里的 32 位 ID 查 ==="
curl -s --noproxy '*' -m 10 "http://localhost:16687/api/traces/$TID" 2>&1 | head -c 200
echo
echo

echo "=== 4. 用 Jaeger 返回的 ID 反查，看格式 ==="
JID=$(curl -s --noproxy '*' -m 10 -G 'http://localhost:16687/api/traces' --data-urlencode 'service=shop-api' --data-urlencode 'limit=1' 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin).get('data',[])
print(d[0]['traceID'] if d else '')
" 2>/dev/null)
echo "  Jaeger ID = $JID (长度 $(echo -n $JID | wc -c))"
echo "  日志 ID   = $TID (长度 $(echo -n $TID | wc -c))"
echo

echo "=== 5. 用 Jaeger 的 ID 去 Loki 搜（反方向）==="
if [ -n "$JID" ]; then
  curl -s --noproxy '*' -m 10 -G 'http://localhost:3101/loki/api/v1/query_range' --data-urlencode "query={job=\"shop\"} |= \"$JID\"" --data-urlencode 'limit=3' --data-urlencode "start=$(( $(date +%s) - 900 ))000000000" --data-urlencode "end=$(date +%s)000000000" 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)
r=d.get('data',{}).get('result',[])
n=sum(len(s.get('values',[])) for s in r)
print('  命中 =', n)
" 2>&1
fi
echo

echo "=== 6. 时间窗口：Jaeger 的 trace 是什么时候的 ==="
curl -s --noproxy '*' -m 10 -G 'http://localhost:16687/api/traces' --data-urlencode 'service=shop-api' --data-urlencode 'limit=2' --data-urlencode "start=$(( $(date +%s) - 600 ))000000" --data-urlencode "end=$(date +%s)000000" 2>&1 | python3 -c "
import sys,json,time
d=json.load(sys.stdin).get('data',[])
print('  最近10分钟 trace 数 =', len(d))
for t in d[:2]:
    st=min(s['startTime'] for s in t['spans'])/1e6
    print('   ', t['traceID'][:20], 'start=', time.strftime('%H:%M:%S', time.localtime(st)))
" 2>&1
