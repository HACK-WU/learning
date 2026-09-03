#!/usr/bin/env bash
# 课 3 数据准备（v2）：把时间范围落盘到 meta 文件，供验证脚本精确复用
set -u
BASE="http://localhost:8428"
NOW=$(date +%s); NOW=$(( NOW - NOW % 15 ))
START=$(( NOW - 3600 ))
GAP_START=$(( START + 1200 ))          # gap 起点
GAP_END=$(( GAP_START + 600 ))         # gap 终点（断 10 分钟）
GAP_MID=$(( GAP_START + 300 ))         # gap 中点（取样验证用）

# 落盘元数据
cat > /tmp/l3_meta.env <<EOF
L3_NOW=$NOW
L3_START=$START
L3_GAP_START=$GAP_START
L3_GAP_END=$GAP_END
L3_GAP_MID=$GAP_MID
EOF

echo "时间范围: $(date -d @${START} '+%H:%M:%S') -> $(date -d @${NOW} '+%H:%M:%S')"
echo "gap 区间: $(date -d @${GAP_START} '+%H:%M:%S') -> $(date -d @${GAP_END} '+%H:%M:%S')"
echo "meta 已写入 /tmp/l3_meta.env"

# ---------- 1. counter：3 条序列，每 15 秒一个点 ----------
python3 - "$START" "$NOW" <<'PY' > /tmp/l3_counter.txt
import sys
start, end = int(sys.argv[1]), int(sys.argv[2])
rates = [("api", "i1", 10), ("api", "i2", 25), ("web", "i3", 7)]
lines = []
for job, inst, per_sec in rates:
    val, ts = 1000, start
    while ts <= end:
        lines.append(f'l3_counter_total{{job="{job}",instance="{inst}"}} {val} {ts}')
        val += per_sec * 15
        ts += 15
print("\n".join(lines))
PY

# ---------- 2. gauge 带 gap ----------
python3 - "$START" "$NOW" "$GAP_START" "$GAP_END" <<'PY' > /tmp/l3_gappy.txt
import sys
start, end, gs, ge = map(int, sys.argv[1:5])
lines = []
ts = start
while ts <= end:
    if not (gs <= ts <= ge):
        lines.append(f'l3_gappy{{job="api",instance="i1"}} {50 + (ts % 100)} {ts}')
    ts += 15
print("\n".join(lines))
PY

# ---------- 3. 多主机内存 ----------
python3 - "$START" "$NOW" <<'PY' > /tmp/l3_mem.txt
import sys
start, end = int(sys.argv[1]), int(sys.argv[2])
base = {"h1": 100, "h2": 350, "h3": 720, "h4": 90, "h5": 480}
lines = []
for host, v in base.items():
    t = end - 300
    while t <= end:
        lines.append(f'l3_mem_bytes{{host="{host}",dc="dc1"}} {v} {t}')
        t += 15
print("\n".join(lines))
PY

for f in /tmp/l3_counter.txt /tmp/l3_gappy.txt /tmp/l3_mem.txt; do
  echo "写入 $f ($(grep -c . "$f") 行)"
  curl -s -m 60 -o /dev/null -w "  http=%{http_code}\n" \
    -X POST "$BASE/api/v1/import/prometheus" --data-binary "@$f"
done

curl -s -m 30 -o /dev/null "$BASE/internal/force_flush"
sleep 2
echo "--- series/count ---"; curl -s -m 10 "$BASE/api/v1/series/count"; echo
