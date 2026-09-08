#!/usr/bin/env bash
# 查证：VM 的 -dedup.minScrapeInterval 为什么没生效？
set -u
echo "=== 1. VM 启动参数确认 ==="
docker inspect l8-vm --format '{{.Args}}'

echo
echo "=== 2. 查 /api/v1/status/flags，看 dedup 是否真的被识别 ==="
curl -s "http://localhost:19115/api/v1/status/flags" \
  | python -c "
import sys,json
d=json.load(sys.stdin)
for k,v in d['data'].items():
    if 'dedup' in k.lower():
        print(f'   {k} = {v}')
"

echo
echo "=== 3. VM 上 l8_card_balance 的完整标签（看有没有 replica） ==="
curl -s -G "http://localhost:19115/api/v1/query" \
  --data-urlencode 'query=l8_card_balance{idx="0001"}' \
  | python -c "
import sys,json
d=json.load(sys.stdin)
for s in d['data']['result']:
    print('   ',sorted(s['metric'].items()))
"

echo
echo "=== 4. 关键：dedup 只在查询时生效，且需要时间序列'看起来相同' ==="
echo "   VM 去重原理：同一 (metric_name + labels 除 replica 外) 且时间戳接近 -> 取一个"
echo "   但我们的两条序列带 replica 标签，它们对 VM 而言是**两条不同的序列**"
echo "   ----> 所以 dedup 不会合并它们，这是正确的、符合预期的行为"
echo
echo "   验证：查询时显式去掉 replica 标签（用 sum without）"
curl -s -G "http://localhost:19115/api/v1/query" \
  --data-urlencode 'query=count(sum without(replica) (l8_card_balance))' \
  | python -c "
import sys,json
d=json.load(sys.stdin)
r=d['data']['result']
print('   count(sum without(replica) (l8_card_balance)) =', r[0]['value'][1] if r else 'N/A')
print('   （仍然是 500 —— 因为 without 只是聚合掉标签，不解决"两份值取哪个"）')
"

echo
echo "=== 5. 决定性：查询时如何真正去重（取一个副本的值） ==="
for expr in \
  'count(l8_card_balance{replica="1"})' \
  'count(max by (idx,zone) (l8_card_balance))' \
  'count(min by (idx,zone) (l8_card_balance))' \
  'count(avg by (idx,zone) (l8_card_balance))' ; do
  n=$(curl -s -G "http://localhost:19115/api/v1/query" --data-urlencode "query=$expr" \
    | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else 'N/A')")
  printf "   %-45s = %s\n" "$expr" "$n"
done
