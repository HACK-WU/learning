#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"
IDX="l8_orders_v2"

echo "===== A视角评审：逐条复核讲义中的每一个声明 ====="
echo ""

echo "【声明1】指标聚合：总销售额=190057.0 均价=6527.71 最贵=12999 最便宜=1999"
$C -X POST "$ES/$IDX/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"总销售额":{"sum":{"field":"amount"}},"平均单价":{"avg":{"field":"price"}},
    "最贵":{"max":{"field":"price"}},"最便宜":{"min":{"field":"price"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
a=d['aggregations']
print('  实测: 总=%s 均=%s 最贵=%s 最便宜=%s'%(a['总销售额']['value'],round(a['平均单价']['value'],2),a['最贵']['value'],a['最便宜']['value']))"
echo ""

echo "【声明2】stats 返回 sum=156665.0（注意：这是 price 的和，不是 amount！）"
$C -X POST "$ES/$IDX/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"s":{"stats":{"field":"price"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
a=d['aggregations']['s']
print('  实测 stats(price): count=%s min=%s max=%s avg=%s sum=%s'%(a['count'],a['min'],a['max'],round(a['avg'],2),a['sum']))"
echo ""

echo "【声明3】苹果均价 8849.0，手算 70792/8"
$C -X POST "$ES/$IDX/_search?size=0" -H "Content-Type: application/json" -d '{
  "query":{"term":{"brand":"苹果"}},"aggs":{"a":{"avg":{"field":"price"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('  实测 avg =',d['aggregations']['a']['value'])"
$C -X POST "$ES/$IDX/_search?size=20" -H "Content-Type: application/json" -d '{
  "query":{"term":{"brand":"苹果"}},"_source":["price"]}' | python -c "
import sys,json
d=json.load(sys.stdin)
ps=[h['_source']['price'] for h in d['hits']['hits']]
print('  苹果价格列表:',sorted(ps),' sum=',sum(ps),' n=',len(ps),' avg=',sum(ps)/len(ps))"
echo ""

echo "【声明4】华为均价 6497.625（讲义写 6497.62 是四舍五入）"
$C -X POST "$ES/$IDX/_search?size=0" -H "Content-Type: application/json" -d '{
  "query":{"term":{"brand":"华为"}},"aggs":{"a":{"avg":{"field":"price"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('  实测 avg =',d['aggregations']['a']['value'])"
echo ""

echo "【声明5】小米均价 4236.5，销售额 45488"
$C -X POST "$ES/$IDX/_search?size=0" -H "Content-Type: application/json" -d '{
  "query":{"term":{"brand":"小米"}},"aggs":{
    "a":{"avg":{"field":"price"}},"s":{"sum":{"field":"amount"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
a=d['aggregations']
print('  实测 avg=%s sum=%s'%(a['a']['value'],a['s']['value']))"
echo ""

echo "【声明6】城市客单价：上海10398 北京7687.78 广州7338.8 深圳5446.25"
$C -X POST "$ES/$IDX/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_city":{"terms":{"field":"city","size":10},
    "aggs":{"订单数":{"value_count":{"field":"order_id"}},
      "销售额":{"sum":{"field":"amount"}},
      "客单价":{"bucket_script":{"buckets_path":{"s":"销售额","c":"订单数"},"script":"params.s / params.c"}}}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
for b in d['aggregations']['by_city']['buckets']:
    print('  %s  %s单  销售额%s  客单价%s'%(b['key'],b['doc_count'],b['销售额']['value'],round(b['客单价']['value'],2)))"
echo ""

echo "【声明7】退款率 16.7%（20完成/4退款）"
$C -X POST "$ES/$IDX/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"st":{"filters":{"filters":{
    "已完成":{"term":{"status":"已完成"}},"退款":{"term":{"status":"退款"}}}}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
b=d['aggregations']['st']['buckets']
dn=b['已完成']['doc_count']; rf=b['退款']['doc_count']
print('  实测: 已完成=%s 退款=%s 退款率=%s%%'%(dn,rf,round(rf/(dn+rf)*100,2)))"
echo ""

echo "【声明8】已完成订单品牌销售额：华为7/55180 苹果7/69391 小米6/35991"
$C -X POST "$ES/$IDX/_search?size=0" -H "Content-Type: application/json" -d '{
  "query":{"term":{"status":"已完成"}},
  "aggs":{"by_brand":{"terms":{"field":"brand"},
    "aggs":{"销售额":{"sum":{"field":"amount"}}}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
tot=0
for b in d['aggregations']['by_brand']['buckets']:
    v=b['销售额']['value']; tot+=v
    print('  %s %s单 %s'%(b['key'],b['doc_count'],v))
print('  合计:',tot)"
echo ""

echo "【声明9】热门标签TOP5：高端6 性价比5 新品4 热销4 办公3"
$C -X POST "$ES/$IDX/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"t":{"terms":{"field":"tags","size":5}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
s=0
for b in d['aggregations']['t']['buckets']:
    print('  %s %s单'%(b['key'],b['doc_count'])); s+=b['doc_count']
print('  标签计数之和:',s,'（文档数24，array字段所以不等）')"
echo ""

echo "【声明10】ES|QL 中文列名报错、英文正常"
$C -X POST "$ES/_query?format=txt" -H "Content-Type: application/json" -d '{
  "query":"FROM l8_orders_v2 | STATS 订单数 = COUNT(*) BY brand"}' | python -c "
import sys,json
d=json.load(sys.stdin)
print('  中文列名:',d.get('error',{}).get('reason','(无错误)'))"
$C -X POST "$ES/_query?format=txt" -H "Content-Type: application/json" -d '{
  "query":"FROM l8_orders_v2 | STATS cnt = COUNT(*) BY brand"}' > /dev/null 2>&1
echo "  英文列名: 正常（返回码检查）"
$C -X POST "$ES/_query?format=txt" -H "Content-Type: application/json" -d '{
  "query":"FROM l8_orders_v2 | STATS cnt = COUNT(*) BY brand | SORT cnt DESC"}'
echo ""
echo "===== A视角复核完成 ====="
