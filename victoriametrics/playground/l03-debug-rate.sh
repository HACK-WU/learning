#!/usr/bin/env bash
# 排查：rate(l3_counter_total[5m]) 为何返回 25 而不是 10
set -u
BASE="http://localhost:8428"
FMT=/mnt/d/projects/learning/victoriametrics/playground/l03-fmt.py
. /tmp/l3_meta.env

echo "=== 1. 用 export 读回 i1 的原始样本（最后 8 个点）==="
curl -s -m 30 -G "$BASE/api/v1/export" \
  --data-urlencode 'match[]=l3_counter_total{instance="i1"}' \
  --data-urlencode "start=$((L3_NOW-600))" \
  --data-urlencode "end=$L3_NOW" \
| python3 -c '
import sys, json
rows=[]
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    d=json.loads(line)
    rows.append((d["values"], d["timestamps"]))
ts=rows[0][1]; vs=rows[0][0]
print("  样本数:", len(ts))
for t,v in list(zip(ts,vs))[-8:]:
    import datetime
    print("   ", datetime.datetime.fromtimestamp(t).strftime("%H:%M:%S"), v)
'

echo
echo "=== 2. 不同 lookbehind 窗口下的 rate ==="
for w in 1m 2m 5m 10m; do
  echo "--- rate(l3_counter_total[$w]) ---"
  curl -s -m 20 -G "$BASE/api/v1/query" \
    --data-urlencode "query=rate(l3_counter_total{instance=\"i1\"}[$w])" \
    --data-urlencode "nocache=1" | python3 "$FMT" | sed -n '2,3p'
done

echo
echo "=== 3. increase 在不同窗口（期望：窗口秒数 x 10/秒）==="
for w in 1m 2m 5m; do
  echo "--- increase(l3_counter_total{instance=\"i1\"}[$w]) ---"
  curl -s -m 20 -G "$BASE/api/v1/query" \
    --data-urlencode "query=increase(l3_counter_total{instance=\"i1\"}[$w])" \
    --data-urlencode "nocache=1" | python3 "$FMT" | sed -n '2,3p'
done

echo
echo "=== 4. 检查是否写入了重复批次（同一时间戳两条不同值）==="
echo "  当前 series/count:"; curl -s -m 10 "$BASE/api/v1/series/count"; echo
echo "  l3_counter_total 的序列数:"
curl -s -m 20 -G "$BASE/api/v1/series" \
  --data-urlencode 'match[]=l3_counter_total' \
| python3 -c 'import sys,json;print("   ", len(json.load(sys.stdin)["data"]))'
