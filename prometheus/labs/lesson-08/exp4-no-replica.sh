#!/usr/bin/env bash
# 知识点 3 决定性对照：external_labels 里没有 replica 会怎样？
# 建两个"忘记写 replica"的副本，双写到同一个 VM（新实例，避免污染）
set -u
L8=/mnt/d/projects/learning/prometheus/labs/lesson-08

echo "=== 准备：起一个不带 replica 的 VM（干净后端） ==="
docker rm -f l8-vm-norep >/dev/null 2>&1 || true
docker run -d --name l8-vm-norep --network l8net -p 19117:8428 \
  victoriametrics/victoria-metrics:v1.151.0 \
  -storageDataPath=/vmdata -retentionPeriod=1 \
  -dedup.minScrapeInterval=5s >/dev/null

echo "=== 起两个 external_labels 完全相同（无 replica）的副本 ==="
docker rm -f l8-norep-1 l8-norep-2 >/dev/null 2>&1 || true

docker run -d --name l8-norep-1 --network l8net -p 19118:9090 \
  -v "$L8/norep-1.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus --storage.tsdb.retention.time=2h >/dev/null

docker run -d --name l8-norep-2 --network l8net -p 19119:9090 \
  -v "$L8/norep-2.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus --storage.tsdb.retention.time=2h >/dev/null

echo "   等待 40 秒（让双写积累样本，dedup 需要足够样本才能观察）..."
sleep 40

echo
echo "=== 关键对照：两条序列标签完全相同时 ==="
echo "  --- 后端（无 replica，dedup.minScrapeInterval=5s）---"
curl -s -G "http://localhost:19117/api/v1/query" \
  --data-urlencode 'query=l8_card_balance{idx="0001"}' \
  | python -c "
import sys,json
d=json.load(sys.stdin)
r=d['data']['result']
print(f'   命中 {len(r)} 条')
for s in r:
    print('   ',{k:v for k,v in sorted(s['metric'].items()) if k!='__name__'})
    print('     值 =',s['value'][1])
"

echo
echo "  --- 总数对照 ---"
n=$(curl -s -G "http://localhost:19117/api/v1/query" \
  --data-urlencode 'query=count(l8_card_balance)' \
  | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else 'N/A')")
echo "   无 replica（两条序列标签相同）-> count = $n 条"
echo "   （500 = dedup 生效合并了；1000 = 未合并，产生重复数据）"

echo
echo "=== 对照：带 replica 的 VM（19115）==="
n2=$(curl -s -G "http://localhost:19115/api/v1/query" \
  --data-urlencode 'query=count(l8_card_balance)' \
  | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else 'N/A')")
echo "   有 replica -> count = $n2 条（两个副本各 500，靠 replica 区分）"

echo
echo "=== 决定性结论 ==="
echo "   有 replica: 1000 条，但查询时 max without(replica) 可得到确定的单一值"
echo "   无 replica: 两条序列标签完全相同 -> 后端 dedup 按时间戳合并（本例 5s 窗口）"
echo "              -> 看似'干净'，实则**丢失了副本信息**，且依赖后端实现"
echo "              -> 若后端不做 dedup（如某些存储），则直接产生 1000 条重复数据"
