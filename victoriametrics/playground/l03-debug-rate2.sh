#!/usr/bin/env bash
# 排查 v2：确认重复写入叠加，并在干净指标上复现准确结果
set -u
BASE="http://localhost:8428"
FMT=/mnt/d/projects/learning/victoriametrics/playground/l03-fmt.py
. /tmp/l3_meta.env

echo "=== 1. export 时间戳是毫秒（修正）==="
curl -s -m 30 -G "$BASE/api/v1/export" \
  --data-urlencode 'match[]=l3_counter_total{instance="i1"}' \
  --data-urlencode "start=$((L3_NOW-300))" \
  --data-urlencode "end=$L3_NOW" \
| python3 -c '
import sys, json, datetime
rows=[]
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    d=json.loads(line)
    rows.append((d["timestamps"], d["values"]))
ts, vs = rows[0]
print("  样本数:", len(ts))
for t,v in list(zip(ts,vs))[-6:]:
    print("   ", datetime.datetime.fromtimestamp(t/1000).strftime("%H:%M:%S"), v)
print("  -> 注意：export 的 timestamps 单位是毫秒")
'

echo
echo "=== 2. 关键实验：同一时间戳重复写入，值是否叠加？==="
T=$(( $(date +%s) / 15 * 15 ))
curl -s -m 10 -o /dev/null -X POST "$BASE/api/v1/import/prometheus" \
  --data-binary "l3_dup_test{job=\"t\"} 100 ${T}"
curl -s -m 10 -o /dev/null -X POST "$BASE/api/v1/import/prometheus" \
  --data-binary "l3_dup_test{job=\"t\"} 999 ${T}"
curl -s -m 10 -o /dev/null "$BASE/internal/force_flush"
sleep 2
echo "  -- 写入 100 后又写入 999（同一 ts），查询：--"
curl -s -m 20 -G "$BASE/api/v1/query" \
  --data-urlencode 'query=l3_dup_test' --data-urlencode "time=$T" \
  --data-urlencode "nocache=1" | python3 "$FMT" | sed -n '2,3p'

echo
echo "=== 3. 用全新指标重测 rate（干净数据，每秒 +10）==="
CLEAN_START=$(( $(date +%s) / 15 * 15 - 1800 ))
CLEAN_END=$(( $(date +%s) / 15 * 15 ))
python3 - "$CLEAN_START" "$CLEAN_END" <<'PY' > /tmp/l3_clean.txt
import sys
start, end = int(sys.argv[1]), int(sys.argv[2])
lines=[]
val, ts = 0, start
while ts <= end:
    lines.append(f'l3_clean_counter{{job="t"}} {val} {ts}')
    val += 10*15
    ts += 15
print("\n".join(lines))
PY
curl -s -m 60 -o /dev/null -X POST "$BASE/api/v1/import/prometheus" --data-binary "@/tmp/l3_clean.txt"
curl -s -m 30 -o /dev/null "$BASE/internal/force_flush"
sleep 2
echo "  写入 $(grep -c . /tmp/l3_clean.txt) 行，每秒 +10"
for w in 1m 2m 5m; do
  echo "--- rate(l3_clean_counter[$w])  期望 10 ---"
  curl -s -m 20 -G "$BASE/api/v1/query" \
    --data-urlencode "query=rate(l3_clean_counter[$w])" \
    --data-urlencode "time=$CLEAN_END" --data-urlencode "nocache=1" \
  | python3 "$FMT" | sed -n '2,3p'
done
for w in 1m 2m 5m; do
  echo "--- increase(l3_clean_counter[$w])  期望 窗口秒数*10 ---"
  curl -s -m 20 -G "$BASE/api/v1/query" \
    --data-urlencode "query=increase(l3_clean_counter[$w])" \
    --data-urlencode "time=$CLEAN_END" --data-urlencode "nocache=1" \
  | python3 "$FMT" | sed -n '2,3p'
done
