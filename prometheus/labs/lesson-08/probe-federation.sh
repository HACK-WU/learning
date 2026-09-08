#!/usr/bin/env bash
# 知识点 1 探针：federation 端点到底返回什么
set -u
echo "=== E0-1: /federate 端点返回的内容（前 25 行） ==="
curl -s -G "http://localhost:19110/federate" \
  --data-urlencode 'match[]={__name__=~"l8_.*"}' \
  | head -n 25

echo
echo "=== E0-2: 计数——叶子本地有多少条 l8_ 序列，federate 返回多少 ==="
LOCAL=$(curl -s -G "http://localhost:19110/api/v1/query" \
  --data-urlencode 'query=count({__name__=~"l8_.*"})' \
  | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else 0)")
FED=$(curl -s -G "http://localhost:19110/federate" \
  --data-urlencode 'match[]={__name__=~"l8_.*"}' | grep -c '^l8_')
echo "  叶子本地 l8_ 序列数 = $LOCAL"
echo "  federate 返回样本数 = $FED"

echo
echo "=== E0-3: 关键——federate 返回的是瞬时值还是历史序列？ ==="
echo "  连续请求两次，看时间戳与值是否变化："
for i in 1 2; do
  curl -s -G "http://localhost:19110/federate" \
    --data-urlencode 'match[]={__name__="l8_card_balance",idx="0001"}' \
    | grep -v '^#' | tr '\n' ' '
  echo "   <-- 第 $i 次"
  sleep 6
done

echo
echo "=== E0-4: honor_labels 的必要性（对照） ==="
echo "  --- 叶子本地标签（leaf-a 上的 l8_card_balance idx=0001） ---"
curl -s -G "http://localhost:19110/api/v1/query" \
  --data-urlencode 'query=l8_card_balance{idx="0001"}' \
  | python -c "
import sys,json
d=json.load(sys.stdin)
r=d['data']['result']
print('   ',sorted(r[0]['metric'].items()) if r else 'NONE')"

echo "  --- federate 端点返回的标签（叶子侧输出） ---"
curl -s -G "http://localhost:19110/federate" \
  --data-urlencode 'match[]={__name__="l8_card_balance",idx="0001"}' \
  | grep -v '^#'

echo
echo "=== E0-5: 全局节点抓到的数据（honor_labels: true 已开启） ==="
curl -s -G "http://localhost:19114/api/v1/query" \
  --data-urlencode 'query=l8_card_balance{idx="0001"}' \
  | python -c "
import sys,json
d=json.load(sys.stdin)
r=d['data']['result']
print('   命中',len(r),'条')
for s in r:
    print('   ',sorted(s['metric'].items()))"
