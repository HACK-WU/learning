#!/bin/bash
echo "########## 为什么 Loki 搜不到 trace_id ##########"
echo

TID=$(docker logs p3-shop 2>&1 | grep -o '"trace_id": "[a-f0-9]\{32\}"' | tail -1 | grep -o '[a-f0-9]\{32\}')
echo "  样本 trace_id = $TID"
echo

echo "=== 1. 用 LogQL 的 |~ 正则匹配（内容搜索，不是标签过滤）==="
curl -s --noproxy '*' -m 10 -G 'http://localhost:3101/loki/api/v1/query_range' --data-urlencode "query={job=\"shop\"} |~ \"$TID\"" --data-urlencode 'limit=3' --data-urlencode "start=$(( $(date +%s) - 900 ))000000000" --data-urlencode "end=$(date +%s)000000000" 2>&1 | head -c 300
echo
echo

echo "=== 2. 用 |= 子串匹配 ==="
curl -s --noproxy '*' -m 10 -G 'http://localhost:3101/loki/api/v1/query_range' --data-urlencode "query={job=\"shop\"} |= \"$TID\"" --data-urlencode 'limit=3' --data-urlencode "start=$(( $(date +%s) - 900 ))000000000" --data-urlencode "end=$(date +%s)000000000" 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)
r=d.get('data',{}).get('result',[])
print('  命中 stream 数 =', len(r))
for s in r[:1]:
    print('  stream:', s.get('stream'))
    for v in s.get('values',[])[:2]: print('   ', v[1][:150])
" 2>&1
echo

echo "=== 3. 不带任何过滤，看最近日志长什么样 ==="
curl -s --noproxy '*' -m 10 -G 'http://localhost:3101/loki/api/v1/query_range' --data-urlencode 'query={job="shop"}' --data-urlencode 'limit=2' --data-urlencode "start=$(( $(date +%s) - 300 ))000000000" --data-urlencode "end=$(date +%s)000000000" 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)
for s in d.get('data',{}).get('result',[])[:1]:
    for v in s.get('values',[])[:2]: print('   ', v[1][:200])
" 2>&1
echo

echo "=== 4. 时间范围是不是问题（Loki 默认只查 recent）==="
echo "  试更长的时间窗 now-1h"
curl -s --noproxy '*' -m 10 -G 'http://localhost:3101/loki/api/v1/query_range' --data-urlencode "query={job=\"shop\"} |= \"$TID\"" --data-urlencode 'limit=3' --data-urlencode "start=$(( $(date +%s) - 3600 ))000000000" --data-urlencode "end=$(date +%s)000000000" 2>&1 | python3 -c "
import sys,json
d=json.load(sys.stdin)
r=d.get('data',{}).get('result',[])
print('  1h 窗口命中 =', len(r))
" 2>&1
