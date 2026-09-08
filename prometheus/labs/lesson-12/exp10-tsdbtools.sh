#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
PT="docker run --rm -v $D/data:/data -v $D:/w --entrypoint promtool prom/prometheus:v3.14.0"

echo "===== [1] tsdb list（列出 block） ====="
$PT tsdb list /data 2>&1 | head -20
echo "（本实例运行时间短，head 尚未落盘，预期 block 很少或没有）"

echo
echo "===== [2] 用 promtool 造一个真实 block，再测 analyze ====="
mkdir -p $D/om $D/blocks-out
python3 - <<'PY'
import random
random.seed(7)
lines = ["# HELP l12_demo synthetic\n", "# TYPE l12_demo gauge\n"]
t0 = 1788700000
for s in range(200):        # 200 序列
    for t in range(0, 3600, 60):   # 每小时 1 点，共 60 点 → 跨 1h
        lines.append(f'l12_demo{{idx="{s:04d}",zone="z{s%3}"}} {random.randint(1,100)} {int((t0+t)*1000)}\n')
lines.append("# EOF\n")          # OpenMetrics 必须以 # EOF 结束，否则 promtool 报 "does not end with # EOF"
open("/mnt/d/projects/learning/prometheus/labs/lesson-12/om/input.om","w").writelines(lines)
print("generated", len(lines)-2, "samples")
PY

$PT tsdb create-blocks-from openmetrics /w/om/input.om /w/blocks-out 2>&1 | tail -5
echo "--- 生成的 block ---"
docker exec l12-prom sh -c "ls /w/blocks-out 2>/dev/null" 2>/dev/null || ls $D/blocks-out

echo
echo "===== [3] tsdb list 造出来的 block ====="
$PT tsdb list /w/blocks-out 2>&1 | head
