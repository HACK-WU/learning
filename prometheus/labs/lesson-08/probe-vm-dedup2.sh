#!/usr/bin/env bash
# 查证 VM dedup 的真实语义（修正 flags 端点路径）
set -u
echo "=== 1. VM 的 flags 端点（VM 用 /flags，不是 Prometheus 的 /api/v1/status/flags） ==="
curl -s "http://localhost:19115/flags" | tr ' ' '\n' | grep -i dedup | sed 's/^/   /'

echo
echo "=== 2. VM 版本 ==="
curl -s "http://localhost:19115/health" | python -c "
import sys,json
d=json.load(sys.stdin)
print('   version =', d.get('version'))
" 2>/dev/null || curl -s "http://localhost:19115/" | grep -oE 'victoria-metrics[^<]*' | head -n 1

echo
echo "=== 3. dedup 的真实语义（决定性验证） ==="
echo "   VM 文档：dedup.minScrapeInterval 用于**同一条时间序列**在极短时间内的重复样本"
echo "   （例如：两个副本写入'完全相同标签'的样本，时间戳相差 < minScrapeInterval）"
echo
echo "   我们的场景：两条序列带不同 replica 标签 -> 对 VM 是**两条独立序列**，dedup 不介入"
echo "   这正是 HA 双写去重的正确做法：**保留 replica 标签，查询时聚合掉**"
echo
echo "   对照：如果两个副本 external_labels 完全相同（都没有 replica），会怎样？"
echo "   -> 两条序列标签完全相同，dedup 会按 minScrapeInterval 去重 -> 这才用上 dedup"

echo
echo "=== 4. 决定性对照：同一条序列查两次，值是否稳定 ==="
for i in 1 2 3; do
  v=$(curl -s -G "http://localhost:19115/api/v1/query" \
    --data-urlencode 'query=l8_card_balance{idx="0001",replica="1"}' \
    | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else 'N/A')")
  echo "   第 $i 次: replica=1 -> $v"
  sleep 2
done

echo
echo "=== 5. HA 场景下正确的查询写法（这就是去重的答案） ==="
for expr in \
  'l8_card_balance{idx="0001"}' \
  'max without(replica) (l8_card_balance{idx="0001"})' \
  'avg without(replica) (l8_card_balance{idx="0001"})' ; do
  n=$(curl -s -G "http://localhost:19115/api/v1/query" --data-urlencode "query=$expr" \
    | python -c "
import sys,json
d=json.load(sys.stdin)
r=d['data']['result']
print(len(r), [s['value'][1] for s in r] if r else '')")
  printf "   %-52s -> %s\n" "$expr" "$n"
done
echo
echo "   解释：不加聚合 -> 2 条（两个副本各一条）"
echo "         max/avg without(replica) -> 1 条（把两个副本合并成一个值）"
