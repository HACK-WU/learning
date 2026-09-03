#!/bin/bash
# 课 12 实验 16：vmctl 迁移（-t 分配 TTY，时间参数用变量拼接）
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428

START=$(date -u -d '6 hours ago' +%Y-%m-%dT%H:%M:%SZ)
END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "时间范围: $START ~ $END"

echo ""
echo "===== [1] 迁移前指纹 ====="
curl -s "$VM/api/v1/label/__name__/values" | python3 -c "import sys,json;print('  VM 指标名数 =',len(json.load(sys.stdin)['data']))"
curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print('  VM 序列数 =',json.load(sys.stdin)['data'][0])"

echo ""
echo "===== [2] 执行迁移（-t 分配 TTY） ====="
docker run --rm -t --network host \
  victoriametrics/vmctl:v1.151.0 \
  remote-read \
  --vm-addr="http://localhost:8428" \
  --remote-read-src-addr="http://localhost:9090" \
  --remote-read-filter-time-start="$START" \
  --remote-read-filter-time-end="$END" \
  --remote-read-step-interval=hour \
  --remote-read-concurrency=2 \
  --vm-concurrency=4 2>&1 | tail -25

echo ""
echo "===== [3] 迁移后核对 ====="
curl -s "$VM/api/v1/label/__name__/values" | python3 -c "import sys,json;print('  VM 指标名数 =',len(json.load(sys.stdin)['data']))"
curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print('  VM 序列数 =',json.load(sys.stdin)['data'][0])"

echo ""
echo "===== [4] 验证迁移内容：Prometheus 侧独有的 go_gc_* 指标是否进来了 ====="
echo "-- Prometheus 源端 go_gc_gogc_percent --"
curl -s "http://localhost:9090/api/v1/query?query=go_gc_gogc_percent" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   ', len(r), '条; 值 =', r[0]['value'][1] if r else 'NONE')"
echo "-- VM 端 go_gc_gogc_percent --"
curl -s "$VM/api/v1/query?query=go_gc_gogc_percent" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   ', len(r), '条; 值 =', r[0]['value'][1] if r else 'NONE')"

echo ""
echo "===== [5] 幂等性验证：同样范围再迁一次 ====="
BEFORE=$(curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0])")
echo "  迁前 = $BEFORE"
docker run --rm -t --network host \
  victoriametrics/vmctl:v1.151.0 \
  remote-read \
  --vm-addr="http://localhost:8428" \
  --remote-read-src-addr="http://localhost:9090" \
  --remote-read-filter-time-start="$START" \
  --remote-read-filter-time-end="$END" \
  --remote-read-step-interval=hour \
  --remote-read-concurrency=2 \
  --vm-concurrency=4 2>&1 | grep -iE "imported|total|error|fatal" | tail -5
sleep 2
AFTER=$(curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0])")
echo "  迁后 = $AFTER"
echo "  差值 = $((AFTER-BEFORE))  ← 接近 0 说明迁移幂等（重复迁移不产生新序列）"
