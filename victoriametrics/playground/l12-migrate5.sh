#!/bin/bash
# 课 12 实验 15：vmctl 迁移最终版（vm-learn 不在 vm-cluster-net，用 host 网络 + localhost）
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428

VMIP=$(docker inspect vm-learn --format '{{range $k,$v := .NetworkSettings.Networks}}{{$v.IPAddress}}{{end}}' | head -1)
PROMIP=$(docker inspect prom-learn --format '{{range $k,$v := .NetworkSettings.Networks}}{{$v.IPAddress}}{{end}}' | head -1)
echo "vm-learn IP=$VMIP (网络: $(docker inspect vm-learn --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' | head -1))"
echo "prom-learn IP=$PROMIP (网络: $(docker inspect prom-learn --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' | head -1))"

echo ""
echo "===== [1] 迁移前指纹 ====="
curl -s "$VM/api/v1/label/__name__/values" | python3 -c "import sys,json;print('  VM 迁移前指标名数 =',len(json.load(sys.stdin)['data']))"
curl -s $VM/api/v1/series/count; echo

echo ""
echo "===== [2] 执行迁移（host 网络，两端都走 localhost） ====="
START=$(date -u -d '6 hours ago' +%Y-%m-%dT%H:%M:%SZ)
END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "时间范围: $START ~ $END"

docker run --rm --network host \
  victoriametrics/vmctl:v1.151.0 \
  remote-read \
  --vm-addr=http://localhost:8428 \
  --vm-concurrency=4 \
  --remote-read-src-addr=http://localhost:9090 \
  --remote-read-filter-time-start=$START \
  --remote-read-filter-time-end=$END \
  --remote-read-step-interval=hour \
  --remote-read-concurrency=2 2>&1 | tail -30

echo ""
echo "===== [3] 迁移后核对 ====="
curl -s "$VM/api/v1/label/__name__/values" | python3 -c "import sys,json;print('  VM 迁移后指标名数 =',len(json.load(sys.stdin)['data']))"
curl -s $VM/api/v1/series/count; echo

echo ""
echo "===== [4] 关键点：迁移是否真的带来了新数据 ====="
echo "-- 用迁移专用 label 无法加，改用「Prometheus 独有指标」对比 --"
curl -s "$VM/api/v1/query?query=count(prometheus_tsdb_head_series)" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('  prometheus_tsdb_head_series 序列数 =', len(r))"
echo "-- 抽查迁移过来的样本值 vs Prometheus 源端 --"
echo "  Prometheus 源端 go_goroutines:"
curl -s "$PROM/api/v1/query" --data-urlencode 'query=go_goroutines' 2>/dev/null | head -c 0
curl -s "http://localhost:9090/api/v1/query?query=go_goroutines" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   ', r[0]['value'][1] if r else 'NONE')"
echo "  VM 迁移端 go_goroutines:"
curl -s "http://localhost:8428/api/v1/query?query=go_goroutines" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   ', len(r), '条序列; 第一条 =', r[0]['value'][1] if r else 'NONE')"

echo ""
echo "===== [5] 迁移幂等性：再迁一次同样时间范围，序列数应不变 ====="
curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print('  第二次迁移前 =', json.load(sys.stdin)['data'][0])"
docker run --rm --network host \
  victoriametrics/vmctl:v1.151.0 \
  remote-read \
  --vm-addr=http://localhost:8428 \
  --vm-concurrency=4 \
  --remote-read-src-addr=http://localhost:9090 \
  --remote-read-filter-time-start=$START \
  --remote-read-filter-time-end=$END \
  --remote-read-step-interval=hour \
  --remote-read-concurrency=2 2>&1 | grep -E "imported|Total|error|fatal" | tail -6
sleep 2
curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print('  第二次迁移后 =', json.load(sys.stdin)['data'][0])"
