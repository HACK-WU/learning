#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## 5-B. 用 termvectors 拿各文档 content 的词项数与词频 ##########"
for id in 1 2 3 4 5 6; do
  $C -X POST "$ES/l7_news/_termvectors/$id" -H "Content-Type: application/json" -d '{
    "fields":["content"],"offsets":false,"positions":false,"payloads":false,
    "field_statistics":true,"term_statistics":false}' \
  | python -c "
import sys,json
d=json.load(sys.stdin)
tv=d.get('term_vectors',{}).get('content',{})
terms=tv.get('terms',{})
fs=tv.get('field_statistics',{})
total=sum(v.get('term_freq',0) for v in terms.values())
print('  doc%s: 词项数(dl)=%s  总词频=%s  sum_doc_freq=%s'%(('$id'),len(terms),total,fs.get('sum_doc_freq')))
top=sorted(terms.items(),key=lambda x:-x[1].get('term_freq',0))[:5]
for t,v in top: print('        %s × %s'%(t,v.get('term_freq')))"
done
echo ""

echo "########## 6. 验证「雷军」被 IK 切成什么 ##########"
$C -X POST "$ES/l7_news/_analyze" -H "Content-Type: application/json" -d '{
  "field":"content","text":"雷军"}' | python -c "
import sys,json;d=json.load(sys.stdin)
print('  ik_smart 切「雷军」:',' | '.join(t['token'] for t in d.get('tokens',[])))"
$C -X POST "$ES/l7_news/_analyze" -H "Content-Type: application/json" -d '{
  "field":"content","text":"苹果"}' | python -c "
import sys,json;d=json.load(sys.stdin)
print('  ik_smart 切「苹果」:',' | '.join(t['token'] for t in d.get('tokens',[])))"
echo ""

echo "########## 7. 排序：sort 覆盖相关性 ##########"
echo "--- 不排序（按 _score 降序，默认）---"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "size":6,"query":{"match":{"content":"手机"}}}' | python -c "
import sys,json;d=json.load(sys.stdin)
for h in d['hits']['hits']: print('   %s  doc%s %s'%(round(h['_score'],4),h['_id'],h['_source']['title']))"
echo ""
echo "--- 按 views 降序（_score 变 null）---"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "size":6,"sort":[{"views":{"order":"desc"}}],"query":{"match":{"content":"手机"}}}' | python -c "
import sys,json;d=json.load(sys.stdin)
for h in d['hits']['hits']: print('   score=%s views=%s doc%s %s'%(h['_score'],h['_source']['views'],h['_id'],h['_source']['title']))"
echo ""

echo "########## 8. 排序稳定性验证：相同 sort 值的顺序 ##########"
echo "--- 按 is_top 排序（多文档同值）---"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "size":6,"sort":[{"is_top":{"order":"desc"}}],"query":{"match_all":{}}}' | python -c "
import sys,json;d=json.load(sys.stdin)
print('   sort值:',[h.get('sort') for h in d['hits']['hits']])
for h in d['hits']['hits']: print('   doc%s is_top=%s'%(h['_id'],h['_source']['is_top']))"
echo ""

echo "########## 9. 深度分页：from/size 上限验证 ##########"
echo "--- 尝试 from=10000 ---"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "from":10000,"size":10,"query":{"match_all":{}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
if 'error' in d:
    e=d['error']
    print('   ERROR type:',e.get('type'))
    print('   reason:',str(e.get('reason'))[:300])
    print('   root_cause:',json.dumps(e.get('root_cause',[]),ensure_ascii=False)[:300])
else: print('   成功')"
echo ""
echo "--- 查实际默认上限 ---"
$C "$ES/l7_news/_settings?filter_path=**.max_result_window"
echo ""
$C "$ES/l7_news/_settings?include_defaults=true&filter_path=**.max_result_window" \
| python -c "
import sys,json;d=json.load(sys.stdin)
import re
s=json.dumps(d)
print('   包含 max_result_window 的输出:', re.findall(r'\"max_result_window\":\"?(\d+)\"?',s) or '未找到')"
echo ""

echo "########## DONE-L7-3 ##########"
