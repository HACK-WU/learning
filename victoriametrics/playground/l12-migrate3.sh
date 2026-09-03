#!/bin/bash
# 课 12 实验 13：vmctl remote-read 迁移（正确参数）+ 迁移前后对照
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428
PROM=http://localhost:9090

echo "===== [1] 迁移前：两端指纹 ====="
echo "-- Prometheus 端 --"
curl -s "$PROM/api/v1/label/__name__/values" | python3 -c "import sys,json;d=json.load(sys.stdin)['data'];print('  Prometheus 指标名数 =',len(d))"
curl -s "$PROM/api/v1/query?query=count(up)" | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('  Prometheus up 序列数 =', r[0]['value'][1] if r else 'NONE')"
echo "-- VM 端 --"
curl -s "$VM/api/v1/series/count" | python3 -c "import sys,json;print('  VM 序列总数 =', json.load(sys.stdin)['data'][0])"
echo "-- VM 端是否已有 prometheus 专属指标 --"
curl -s --data-urlencode 'query=count(prometheus_build_info)' "$VM/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('  prometheus_build_info =', r[0]['value'][1] if r else 'NONE')"

echo ""
echo "===== [2] 迁移前：给 Prometheus 灌一批「只存在于源端」的历史数据 ====="
echo "-- 用 remote write 无法写历史，改用 Prometheus 自身抓取不到的目标不现实；"
echo "-- 改用对照：统计 Prometheus 独有的指标名（VM 中没有的） --"
curl -s "$PROM/api/v1/label/__name__/values" | python3 -c "
import sys,json,urllib.request
prom=set(json.load(sys.stdin)['data'])
vm=set(json.load(urllib.request.urlopen('http://localhost:8428/api/v1/label/__name__/values'))['data'] if False else json.load(urllib.request.urlopen('http://localhost:8428/api/v1/label/__name__/values'))['data'])
only_prom=sorted(prom-vm)
print('  Prometheus 独有指标数 =', len(only_prom))
print('  示例 =', only_prom[:8])
" 2>&1 | head -5

echo ""
echo "===== [3] 执行 remote-read 迁移（迁到独立租户 555，避免污染 tenant 0） ====="
START=$(date -u -d '6 hours ago' +%Y-%m-%dT%H:%M:%SZ)
END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "时间范围: $START ~ $END"

docker run --rm --network vm-cluster-net \
  victoriametrics/vmctl:v1.151.0 \
  remote-read \
  --vm-addr=http://vminsert-learn:8480/insert/555/prometheus \
  --vm-account-id=555 \
  --vm-concurrency=4 \
  --remote-read-src-addr=http://prom-learn:9090 \
  --remote-read-filter-time-start=$START \
  --remote-read-filter-time-end=$END \
  --remote-read-step-interval=hour \
  --remote-read-concurrency=2 2>&1 | tail -30

echo ""
echo "===== [4] 迁移后核对：tenant 555 ====="
echo "-- tenant 555 序列数（经 vmselect 查） --"
curl -s "http://localhost:8481/select/555/prometheus/api/v1/series/count"; echo
echo "-- tenant 555 指标名数 --"
curl -s "http://localhost:8481/select/555/prometheus/api/v1/label/__name__/values" \
  | python3 -c "import sys,json;d=json.load(sys.stdin)['data'];print('  tenant 555 指标名数 =',len(d))" 2>&1 | head -2
echo "-- 抽查 prometheus_build_info 是否迁过来 --"
curl -s --data-urlencode 'query=prometheus_build_info' "http://localhost:8481/select/555/prometheus/api/v1/query" \
  | python3 -c "
import sys,json
r=json.load(sys.stdin)['data']['result']
print('  tenant 555 prometheus_build_info 序列数 =', len(r))
for x in r[:2]: print('   ', x['metric'].get('version'), x['value'][1])
" 2>&1 | head -5
echo "-- 抽查一个采样值是否与源端一致 --"
echo "  源端："
curl -s --data-urlencode 'query=prometheus_tsdb_head_series' "$PROM/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   ', r[0]['value'][1] if r else 'NONE')" 2>&1 | head -2
echo "  迁移后 tenant 555："
curl -s --data-urlencode 'query=prometheus_tsdb_head_series' "http://localhost:8481/select/555/prometheus/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   ', r[0]['value'][1] if r else 'NONE')" 2>&1 | head -2
