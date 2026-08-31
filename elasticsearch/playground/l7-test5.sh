#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## 15. 验证 function_score 的计算 ##########"
python -c "
import math
print('=== field_value_factor: log1p, factor=0.5, boost_mode=multiply ===')
print('  公式: new_score = old_score * (1 + 0.5 * log1p(views))')
print('  log1p(x) = log(1+x)')
print()
data=[('doc6',0.7444,6000),('doc1',0.7091,5000),('doc4',0.6901,3000),('doc5',0.3998,20000)]
for name,base,views in data:
    f=1+0.5*math.log1p(views)
    print('  %s: base=%s  views=%s  log1p=%.4f  factor=%.4f  → %.4f'%(name,base,views,math.log1p(views),f,base*f))
print()
print('  注意 doc5: views 最高(20000) 但基础分最低(0.3998)，加权后仍是最后一名')
print('  → 说明 boost_mode=multiply 只是放大，不能颠覆相关性排序')
"
echo ""

echo "########## 16. search_after（深度分页正解 1）##########"
echo "--- 需要先有唯一排序键，用 _id 兜底 ---"
echo "第 1 页:"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "size":2,
  "sort":[{"views":{"order":"desc"},"_id":{"order":"asc"}}],
  "query":{"match_all":{}}}' > /tmp/p1.json
python -c "
import json;d=json.load(open('/tmp/p1.json'))
for h in d['hits']['hits']:
    print('   doc%s views=%s sort=%s'%(h['_id'],h['_source']['views'],h.get('sort')))"
LAST=$(python -c "
import json;d=json.load(open('/tmp/p1.json'))
print(json.dumps(d['hits']['hits'][-1]['sort']))")
echo "   拿到的游标: $LAST"
echo ""
echo "第 2 页（用 search_after 接力）:"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d "{
  \"size\":2,
  \"sort\":[{\"views\":{\"order\":\"desc\"},\"_id\":{\"order\":\"asc\"}}],
  \"query\":{\"match_all\":{}},
  \"search_after\":$LAST}" | python -c "
import sys,json;d=json.load(sys.stdin)
for h in d['hits']['hits']:
    print('   doc%s views=%s sort=%s'%(h['_id'],h['_source']['views'],h.get('sort')))"
echo ""

echo "########## 17. PIT（Point in Time）保持一致视图 ##########"
echo "--- 开一个 PIT ---"
$C -X POST "$ES/l7_news/_pit?keep_alive=1m" > /tmp/pit.json
PITID=$(python -c "import json;print(json.load(open('/tmp/pit.json'))['id'])")
echo "   PIT id: ${PITID:0:30}..."
echo "--- 用 PIT 查询 ---"
$C -X POST "$ES/_search" -H "Content-Type: application/json" -d "{
  \"size\":3,
  \"pit\":{\"id\":\"$PITID\",\"keep_alive\":\"1m\"},
  \"sort\":[{\"views\":{\"order\":\"desc\"}}],
  \"query\":{\"match_all\":{}}}" | python -c "
import sys,json;d=json.load(sys.stdin)
print('   命中:',d['hits']['total']['value'])
for h in d['hits']['hits']: print('   doc%s views=%s'%(h['_id'],h['_source']['views']))"
echo ""
echo "--- 关闭 PIT ---"
$C -X DELETE "$ES/_pit" -H "Content-Type: application/json" -d "{\"id\":\"$PITID\"}"
echo ""

echo "########## 18. Scroll（深度遍历，非实时分页）##########"
echo "--- 开 scroll ---"
$C -X POST "$ES/l7_news/_search?scroll=1m" -H "Content-Type: application/json" -d '{
  "size":2,"query":{"match_all":{}}}' > /tmp/s1.json
SID=$(python -c "import json;print(json.load(open('/tmp/s1.json'))['_scroll_id'])")
python -c "
import json;d=json.load(open('/tmp/s1.json'))
print('   第1批:',[h['_id'] for h in d['hits']['hits']])"
$C -X POST "$ES/_search/scroll" -H "Content-Type: application/json" -d "{
  \"scroll\":\"1m\",\"scroll_id\":\"$SID\"}" | python -c "
import sys,json;d=json.load(sys.stdin)
print('   第2批:',[h['_id'] for h in d['hits']['hits']])"
echo ""
echo "--- 清理 scroll ---"
$C -X DELETE "$ES/_search/scroll" -H "Content-Type: application/json" -d "{\"scroll_id\":\"$SID\"}"
echo ""

echo "########## 19. 验证 max_result_window 可调 ##########"
$C -X PUT "$ES/l7_news/_settings" -H "Content-Type: application/json" -d '{
  "index":{"max_result_window":50000}}'
echo ""
echo "--- 再试 from=10000 ---"
$C -X POST "$ES/l7_news/_search" -H "Content-Type: application/json" -d '{
  "from":10000,"size":1,"query":{"match_all":{}}}' \
| python -c "
import sys,json;d=json.load(sys.stdin)
print('   结果:', '成功但无数据' if d['hits']['hits']==[] else 'ERROR: '+str(d.get('error',{}).get('reason',''))[:150])"
echo ""
echo "--- 改回默认值 ---"
$C -X PUT "$ES/l7_news/_settings" -H "Content-Type: application/json" -d '{
  "index":{"max_result_window":10000}}' > /dev/null
echo "   已恢复 10000"
echo ""
echo "########## DONE-L7-5 ##########"
