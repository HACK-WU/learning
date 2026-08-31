#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "=== profile 放 body 里（正确写法）==="
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "size":0,
  "profile":true,
  "query":{"bool":{"filter":[{"term":{"brand":"Apple"}}]}}}' > /tmp/p1.json
python -c "
import json
d=json.load(open('/tmp/p1.json'))
print('  顶层字段:', list(d.keys()))
if 'error' in d:
    print('  ERROR:', d['error'].get('reason','')[:300])
else:
    for sh in d.get('profile',{}).get('shards',[]):
        print('  -- shard --')
        for q in sh.get('query',[]):
            print('    type:',q.get('type'),'| time:',q.get('time_in_nanos'),'ns')
            print('    desc:',q.get('description'))
            for c in q.get('children',[]):
                print('      child:',c.get('type'),'| time:',c.get('time_in_nanos'),'ns |',c.get('description'))
"
echo ""

echo "=== 对比：query 上下文 ==="
$C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
  "size":0,
  "profile":true,
  "query":{"term":{"brand":"Apple"}}}' > /tmp/p2.json
python -c "
import json
d=json.load(open('/tmp/p2.json'))
print('  顶层字段:', list(d.keys()))
if 'error' in d:
    print('  ERROR:', d['error'].get('reason','')[:300])
else:
    for sh in d.get('profile',{}).get('shards',[]):
        print('  -- shard --')
        for q in sh.get('query',[]):
            print('    type:',q.get('type'),'| time:',q.get('time_in_nanos'),'ns')
            print('    desc:',q.get('description'))
            for c in q.get('children',[]):
                print('      child:',c.get('type'),'| time:',c.get('time_in_nanos'),'ns |',c.get('description'))
"
echo ""

echo "=== 多次执行观察 filter 稳定性（10 次，看 took）==="
for i in $(seq 1 10); do
  $C -X POST "$ES/l6_shop/_search" -H "Content-Type: application/json" -d '{
    "size":0,"query":{"bool":{"filter":[{"term":{"brand":"Apple"}}]}}}' \
  | python -c "import sys,json;d=json.load(sys.stdin);print(d['took'],end=' ')"
done
echo " <- filter 各次 took(ms)"
echo "########## DONE-6 ##########"
