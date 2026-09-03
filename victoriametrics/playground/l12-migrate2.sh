#!/bin/bash
# 课 12 实验 12：vmctl 正确参数格式（双横线）+ 迁移核对
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428

echo "===== [1] vmctl 帮助头（确认子命令） ====="
docker run --rm victoriametrics/vmctl:v1.151.0 --help 2>&1 | head -25

echo ""
echo "===== [2] remote-read 迁移：正确参数 ====="
START=$(date -u -d '3 hours ago' +%Y-%m-%dT%H:%M:%SZ)
END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "时间范围: $START ~ $END"
echo "-- 迁移前 VM tenant 0 序列数 --"
curl -s $VM/api/v1/series/count; echo

docker run --rm --network vm-cluster-net \
  victoriametrics/vmctl:v1.151.0 \
  remote-read \
  --vm-addr=http://vminsert-learn:8480/insert/0/prometheus \
  --vm-concurrency=4 \
  --remote-read-src-addr=http://prom-learn:9090 \
  --remote-read-filter-time-start=$START \
  --remote-read-filter-time-end=$END \
  --remote-read-step=60s \
  --remote-read-use-stream=false 2>&1 | tail -30

echo ""
echo "===== [3] 迁移后核对 ====="
echo "-- 序列总数 --"
curl -s $VM/api/v1/series/count; echo
echo "-- 查一个 Prometheus 独有的指标（prometheus_build_info）是否已在 VM --"
curl -s --data-urlencode 'query=prometheus_build_info' "$VM/api/v1/query" \
  | python3 -c "
import sys,json
r=json.load(sys.stdin)['data']['result']
print('  prometheus_build_info 在 VM 中的序列数 =', len(r))
for x in r[:2]:
    print('   ', x['metric'].get('version'), x['metric'].get('instance'))
" 2>&1 | head -5
