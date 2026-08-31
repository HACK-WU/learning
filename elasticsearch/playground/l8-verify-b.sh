#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"
IDX="l8_orders_v2"

echo "===== B视角评审：零上下文用户能否照着做出来？====="
echo ""

echo "【B1】讲义说 l8_orders_v2 有 24 条，确认数据集仍存在"
$C "$ES/_cat/indices?v" | grep -E "l8_orders|l7_news|l6_shop"
echo ""

echo "【B2】讲义 1.3 节的指标聚合代码块，逐字复制执行"
$C -X POST "$ES/$IDX/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs": {
    "总销售额": { "sum":  { "field": "amount" } },
    "平均单价": { "avg":  { "field": "price"  } },
    "最贵":     { "max":  { "field": "price"  } },
    "最便宜":   { "min":  { "field": "price"  } },
    "订单数":   { "value_count": { "field": "order_id" } },
    "去重品牌数": { "cardinality": { "field": "brand" } },
    "一次返回多个": { "stats": { "field": "price" } }
  }
}' | python -c "
import sys,json
d=json.load(sys.stdin)
a=d['aggregations']
for k,v in a.items():
    if 'value' in v: print('   %-12s %s'%(k,v['value']))
    else: print('   %-12s count=%s min=%s max=%s avg=%s sum=%s'%(k,v['count'],v['min'],v['max'],round(v['avg'],2),v['sum']))"
echo ""

echo "【B3】讲义 1.9 节「对 text 字段聚合报错」能否复现（旧索引 l8_orders）"
$C -X POST "$ES/l8_orders/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs":{"by_brand":{"terms":{"field":"brand"}}}}' | python -c "
import sys,json
d=json.load(sys.stdin)
if 'error' in d:
    print('   报错复现:',d['error']['reason'][:100])
else:
    print('   未报错，桶:',[(b['key'],b['doc_count']) for b in d['aggregations']['by_brand']['buckets']])"
echo ""

echo "【B4】讲义 2.3 ② cumulative_sum 代码块，逐字复制执行"
$C -X POST "$ES/$IDX/_search?size=0" -H "Content-Type: application/json" -d '{
  "aggs": {
    "by_week": {
      "date_histogram": { "field": "sale_date", "calendar_interval": "week" },
      "aggs": {
        "周销售额": { "sum": { "field": "amount" } },
        "累计":    { "cumulative_sum": { "buckets_path": "周销售额" } }
      }
    }
  }
}' | python -c "
import sys,json
d=json.load(sys.stdin)
if 'error' in d: print('   报错:',d['error']['reason'][:100])
else:
    for b in d['aggregations']['by_week']['buckets']:
        print('   %s 本周=%-10s 累计=%s'%(b['key_as_string'][:10],b['周销售额']['value'],b['累计']['value']))"
echo ""

echo "【B5】讲义 3.3 ④ BUCKET() 代码块，逐字复制执行"
$C -X POST "$ES/_query?format=txt" -H "Content-Type: application/json" -d '{
  "query":"FROM l8_orders_v2 | STATS cnt = COUNT(*), total = SUM(amount) BY wk = BUCKET(sale_date, 1 week) | SORT wk ASC"}'
echo ""

echo "【B6】讲义速查卡 JSONC，去掉注释后能否执行"
$C -X POST "$ES/$IDX/_search?size=0" -H "Content-Type: application/json" -d '{
  "query": { "term": { "status": "已完成" } },
  "aggs": {
    "by_brand": {
      "terms": { "field": "brand", "size": 20 },
      "aggs": {
        "销售额":   { "sum": { "field": "amount" } },
        "订单数":   { "value_count": { "field": "order_id" } },
        "客单价":   { "bucket_script": {
          "buckets_path": { "s": "销售额", "c": "订单数" },
          "script": "params.s / params.c" } },
        "by_cat": { "terms": { "field": "category" } }
      }
    },
    "最高的": { "max_bucket": { "buckets_path": "by_brand>销售额" } }
  }
}' | python -c "
import sys,json
d=json.load(sys.stdin)
if 'error' in d: print('   报错:',d['error']['reason'][:150])
else:
    a=d['aggregations']
    print('   max_bucket:',a['最高的']['keys'],a['最高的']['value'])
    for b in a['by_brand']['buckets']:
        print('   %s %s单 销售额%s 客单价%s 品类%s'%(b['key'],b['doc_count'],b['销售额']['value'],round(b['客单价']['value'],2),len(b['by_cat']['buckets'])))"
echo ""
echo "===== B视角评审完成 ====="
