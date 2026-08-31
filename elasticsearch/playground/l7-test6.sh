#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "=== 诊断 search_after 失败原因 ==="
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "size":2,
  "sort":[{"views":{"order":"desc"},"_id":{"order":"asc"}}],
  "query":{"match_all":{}}}' > /tmp/d.json
cat /tmp/d.json | head -c 900
echo ""
echo ""

echo "=== 试试 _doc 排序（最高效）==="
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "size":2,
  "sort":[{"views":{"order":"desc"},"_doc":{"order":"asc"}}],
  "query":{"match_all":{}}}' > /tmp/d2.json
python -c "
import json;d=json.load(open('/tmp/d2.json'))
if 'error' in d: print('  ERROR:',json.dumps(d['error'],ensure_ascii=False)[:300])
else:
    for h in d['hits']['hits']: print('   doc%s views=%s sort=%s'%(h['_id'],h['_source']['views'],h.get('sort')))"
echo ""

echo "=== 完整的 search_after 流程（用 views + _doc）==="
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "size":2,
  "sort":[{"views":{"order":"desc"},"_doc":{"order":"asc"}}],
  "query":{"match_all":{}}}' > /tmp/sa1.json
python -c "
import json;d=json.load(open('/tmp/sa1.json'))
if 'error' in d: print('  ERROR:',json.dumps(d['error'],ensure_ascii=False)[:300])
else:
    print('  第1页:')
    for h in d['hits']['hits']: print('    doc%s views=%s sort=%s'%(h['_id'],h['_source']['views'],h.get('sort')))
    import json as j
    open('/tmp/last.txt','w').write(j.dumps(d['hits']['hits'][-1]['sort']))"
LAST=$(cat /tmp/last.txt)
echo "  游标: $LAST"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d "{
  \"size\":2,
  \"sort\":[{\"views\":{\"order\":\"desc\"},\"_doc\":{\"order\":\"asc\"}}],
  \"query\":{\"match_all\":{}},
  \"search_after\":$LAST}" > /tmp/sa2.json
python -c "
import json;d=json.load(open('/tmp/sa2.json'))
if 'error' in d: print('  ERROR:',json.dumps(d['error'],ensure_ascii=False)[:400])
else:
    print('  第2页:')
    for h in d['hits']['hits']: print('    doc%s views=%s sort=%s'%(h['_id'],h['_source']['views'],h.get('sort')))"
echo ""
echo "=== 验证：search_after 能突破 10000 限制吗？==="
echo "  search_after 不受 max_result_window 约束（因为它不做 offset 计算）"
echo "########## DONE-L7-6 ##########"
