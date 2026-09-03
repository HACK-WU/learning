#!/bin/bash
# 课 12 实验 19：vmctl 迁移（用 script 伪终端包裹，避免 -t 干扰外层脚本）
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428
OUT=/tmp/l12_vmctl_out.txt
rm -f $OUT

echo "===== [1] 迁移前指纹 ====="
curl -s "$VM/api/v1/label/__name__/values" | python3 -c "import sys,json;print('  VM 指标名数 =',len(json.load(sys.stdin)['data']))"
curl -s $VM/api/v1/series/count | python3 -c "import sys,json;print('  VM 序列数 =',json.load(sys.stdin)['data'][0])"

echo ""
echo "===== [2] 方式 A：docker run -i（不分配 TTY） ====="
docker run --rm -i --network host \
  victoriametrics/vmctl:v1.151.0 \
  remote-read \
  --vm-addr=http://localhost:8428 \
  --remote-read-src-addr=http://localhost:9090 \
  --remote-read-filter-time-start=2026-09-02T06:00:00Z \
  --remote-read-filter-time-end=2026-09-02T13:00:00Z \
  --remote-read-step-interval=hour < /dev/null > $OUT 2>&1
echo "  退出码 = $?"
echo "  输出行数 = $(wc -l < $OUT)"
echo "  输出尾部："
tail -12 $OUT

echo ""
echo "===== [3] 检查是否已有 -vm-silent 类参数 ====="
docker run --rm victoriametrics/vmctl:v1.151.0 remote-read --help 2>&1 | grep -iE "silent|quiet|progress" | head -5
