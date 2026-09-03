#!/bin/bash
# 课 12 实验 20：vmctl 迁移最终版（-s 静默 + --disable-progress-bar）
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428
OUT=/tmp/l12_vmctl_out.txt

echo "===== [1] 迁移前指纹 ====="
curl -s "$VM/api/v1/label/__name__/values" | python3 -c "import sys,json;print('  VM 指标名数 =',len(json.load(sys.stdin)['data']))"
curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print('  VM 序列数 =',json.load(sys.stdin)['data'][0])"

echo ""
echo "===== [2] 执行迁移（-s 静默，无确认提示，禁用进度条） ====="
rm -f $OUT
docker run --rm --network host \
  victoriametrics/vmctl:v1.151.0 \
  remote-read \
  -s \
  --disable-progress-bar \
  --vm-addr=http://localhost:8428 \
  --remote-read-src-addr=http://localhost:9090 \
  --remote-read-filter-time-start=2026-09-02T06:00:00Z \
  --remote-read-filter-time-end=2026-09-02T13:00:00Z \
  --remote-read-step-interval=hour > $OUT 2>&1
echo "  退出码 = $?"
echo "--- vmctl 输出 ---"
cat $OUT | tail -20

echo ""
echo "===== [3] 迁移后核对 ====="
curl -s "$VM/api/v1/label/__name__/values" | python3 -c "import sys,json;print('  VM 指标名数 =',len(json.load(sys.stdin)['data']))"
curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print('  VM 序列数 =',json.load(sys.stdin)['data'][0])"

echo ""
echo "===== [4] 内容核对：go_gc_gogc_percent（Prometheus 独有，迁移前 VM 应无） ====="
echo "-- Prometheus 源端 --"
curl -s "http://localhost:9090/api/v1/query?query=go_gc_gogc_percent" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   ', len(r), '条; 值 =', r[0]['value'][1] if r else 'NONE')"
echo "-- VM 端 --"
curl -s "$VM/api/v1/query?query=go_gc_gogc_percent" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('   ', len(r), '条; 值 =', r[0]['value'][1] if r else 'NONE')"

echo ""
echo "===== [5] 幂等性：同样范围再迁一次 ====="
BEFORE=$(curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0])")
echo "  第二次迁移前 = $BEFORE"
rm -f $OUT
docker run --rm --network host \
  victoriametrics/vmctl:v1.151.0 \
  remote-read \
  -s --disable-progress-bar \
  --vm-addr=http://localhost:8428 \
  --remote-read-src-addr=http://localhost:9090 \
  --remote-read-filter-time-start=2026-09-02T06:00:00Z \
  --remote-read-filter-time-end=2026-09-02T13:00:00Z \
  --remote-read-step-interval=hour > $OUT 2>&1
echo "  退出码 = $?"
grep -iE "imported|total" $OUT | tail -4
sleep 2
AFTER=$(curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0])")
echo "  第二次迁移后 = $AFTER"
echo "  新增序列数 = $((AFTER-BEFORE))  ← 接近 0 证明幂等"
