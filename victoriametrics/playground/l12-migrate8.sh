#!/bin/bash
# 课 12 实验 18：vmctl 迁移（输出重定向到文件，避免 TTY 交互导致提前退出）
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428
OUT=/tmp/l12_vmctl_out.txt
rm -f $OUT

echo "===== [1] 迁移前指纹 ====="
curl -s "$VM/api/v1/label/__name__/values" | python3 -c "import sys,json;print('  VM 指标名数 =',len(json.load(sys.stdin)['data']))"
curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print('  VM 序列数 =',json.load(sys.stdin)['data'][0])"

echo ""
echo "===== [2] 执行迁移（脚本内重定向） ====="
docker run --rm -t --network host \
  victoriametrics/vmctl:v1.151.0 \
  remote-read \
  --vm-addr=http://localhost:8428 \
  --remote-read-src-addr=http://localhost:9090 \
  --remote-read-filter-time-start=2026-09-02T06:00:00Z \
  --remote-read-filter-time-end=2026-09-02T13:00:00Z \
  --remote-read-step-interval=hour > $OUT 2>&1
RC=$?
echo "  退出码 = $RC"

echo ""
echo "===== [3] vmctl 输出 ====="
cat $OUT | tail -25

echo ""
echo "===== [4] 迁移后核对 ====="
curl -s "$VM/api/v1/label/__name__/values" | python3 -c "import sys,json;print('  VM 指标名数 =',len(json.load(sys.stdin)['data']))"
curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print('  VM 序列数 =',json.load(sys.stdin)['data'][0])"

echo ""
echo "===== [5] 内容核对 go_gc_gogc_percent ====="
echo "-- Prometheus 源端 --"
curl -s "http://localhost:9090/api/v1/query?query=go_gc_gogc_percent" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   ', len(r), '条; 值 =', r[0]['value'][1] if r else 'NONE')"
echo "-- VM 端 --"
curl -s "$VM/api/v1/query?query=go_gc_gogc_percent" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   ', len(r), '条; 值 =', r[0]['value'][1] if r else 'NONE')"
