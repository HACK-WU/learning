#!/bin/bash
# 课 12 实验 30：用 vm_rows_ignored_total 找「写入被丢弃」的铁证
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428

echo "===== [1] 查丢弃原因分布 ====="
curl -s "$VM/api/v1/query?query=sum%20by%20(reason)%20(vm_rows_ignored_total)" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']['result']
print('  reason -> 数量')
for r in d:
    print('   ', r['metric'].get('reason'), '=', r['value'][1])
" 2>&1 | head -12

echo ""
echo "===== [2] 对照：写入前后该指标的变化（前后差值法） ====="
echo "-- 写入前 --"
B=$(curl -s "$VM/api/v1/query?query=sum%20by%20(reason)%20(vm_rows_ignored_total)" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']['result']
o={}
for r in d: o[r['metric'].get('reason')]=int(float(r['value'][1]))
print(o)
")
echo "  $B"

echo "-- 写入 10 条探针 --"
for i in $(seq 1 10); do
  curl -s -o /dev/null -X POST --data-binary "l12_ignore_probe{job=\"l12\",i=\"$i\"} $i" "$VM/api/v1/import/prometheus"
done
sleep 3
echo "-- 写入后 --"
A=$(curl -s "$VM/api/v1/query?query=sum%20by%20(reason)%20(vm_rows_ignored_total)" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']['result']
o={}
for r in d: o[r['metric'].get('reason')]=int(float(r['value'][1]))
print(o)
")
echo "  $A"

echo ""
echo "===== [3] 关键怀疑：是不是 -retentionPeriod=1d 导致「非当前分区」数据不可见 ====="
echo "-- 查 storage 分区目录 --"
docker exec vm-learn sh -c "ls /victoria-metrics-data/data/small/ 2>&1 | head -5"
docker exec vm-learn sh -c "ls /victoria-metrics-data/data/big/ 2>&1 | head -5"

echo ""
echo "===== [4] 决定性测试：重启一个干净实例，写入后立刻查 ====="
echo "-- 启动干净实例（无 relabel / 无 streamAggr / retention=30d） --"
docker rm -f vm-clean-test > /dev/null 2>&1
docker volume rm l12_clean_vol > /dev/null 2>&1
docker volume create l12_clean_vol > /dev/null
docker run -d --name vm-clean-test --network vm-cluster-net -p 8458:8428 \
  -v l12_clean_vol:/victoria-metrics-data \
  victoriametrics/victoria-metrics:v1.151.0 \
  -storageDataPath=/victoria-metrics-data -httpListenAddr=:8428 -retentionPeriod=30d > /dev/null 2>&1
for i in $(seq 1 25); do
  R=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8458/health 2>/dev/null)
  [ "$R" = "200" ] && break
  sleep 1
done
curl -s -o /dev/null -w "  干净实例 /health HTTP=%{http_code}\n" http://localhost:8458/health
echo "-- 往干净实例写入 --"
curl -s -o /dev/null -w "  写入 HTTP=%{http_code}\n" -X POST \
  --data-binary 'l12_clean_probe{job="l12"} 12345' "http://localhost:8458/api/v1/import/prometheus"
sleep 3
echo "-- 立即查 --"
curl -s --data-urlencode 'query=l12_clean_probe' "http://localhost:8458/api/v1/query" | head -c 300; echo

echo ""
echo "===== [5] 若干净实例能查到 → 证明是 vm-learn 的配置问题 ====="
echo "-- 再往干净实例写一条带 40+ labels 的（验证 maxLabelsPerTimeseries=40） --"
LABELS=""
for i in $(seq 1 45); do LABELS="$LABELS,l$i=\"v$i\""; done
PAYLOAD="l12_45labels{job=\"l12\"$LABELS} 1"
curl -s -o /dev/null -w "  45 labels 写入 HTTP=%{http_code}\n" -X POST --data-binary "$PAYLOAD" "http://localhost:8458/api/v1/import/prometheus"
sleep 2
curl -s --data-urlencode 'query=l12_45labels' "http://localhost:8458/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   45 labels 查询到 =', len(r), '条 ← 0 说明超过 40 被丢弃')"