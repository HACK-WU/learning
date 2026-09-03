#!/bin/bash
# 课 12 实验 17：vmctl 迁移（固定时间参数，TTY）
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428

echo "===== [1] 迁移前指纹 ====="
curl -s "$VM/api/v1/label/__name__/values" | python3 -c "import sys,json;print('  VM 指标名数 =',len(json.load(sys.stdin)['data']))"
curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print('  VM 序列数 =',json.load(sys.stdin)['data'][0])"

echo ""
echo "===== [2] 执行迁移 ====="
docker run --rm -t --network host \
  victoriametrics/vmctl:v1.151.0 \
  remote-read \
  --vm-addr=http://localhost:8428 \
  --remote-read-src-addr=http://localhost:9090 \
  --remote-read-filter-time-start=2026-09-02T06:00:00Z \
  --remote-read-filter-time-end=2026-09-02T13:00:00Z \
  --remote-read-step-interval=hour 2>&1 | tail -20

echo ""
echo "===== [3] 迁移后核对 ====="
curl -s "$VM/api/v1/label/__name__/values" | python3 -c "import sys,json;print('  VM 指标名数 =',len(json.load(sys.stdin)['data']))"
curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print('  VM 序列数 =',json.load(sys.stdin)['data'][0])"

echo ""
echo "===== [4] 内容核对：Prometheus 独有指标 go_gc_gogc_percent ====="
echo "-- Prometheus 源端 --"
curl -s "http://localhost:9090/api/v1/query?query=go_gc_gogc_percent" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   ', len(r), '条; 值 =', r[0]['value'][1] if r else 'NONE')"
echo "-- VM 端 --"
curl -s "$VM/api/v1/query?query=go_gc_gogc_percent" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   ', len(r), '条; 值 =', r[0]['value'][1] if r else 'NONE')"

echo ""
echo "===== [5] 幂等性：再迁一次 ====="
BEFORE=$(curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0])")
echo "  迁前 = $BEFORE"
docker run --rm -t --network host \
  victoriametrics/vmctl:v1.151.0 \
  remote-read \
  --vm-addr=http://localhost:8428 \
  --remote-read-src-addr=http://localhost:9090 \
  --remote-read-filter-time-start=2026-09-02T06:00:00Z \
  --remote-read-filter-time-end=2026-09-02T13:00:00Z \
  --remote-read-step-interval=hour 2>&1 | grep -iE "imported|total" | tail -3
sleep 2
AFTER=$(curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0])")
echo "  迁后 = $AFTER  差值 = $((AFTER-BEFORE))"
