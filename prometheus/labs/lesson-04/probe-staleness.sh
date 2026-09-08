set +x
PROM=http://localhost:9094

echo "########## 精确量化 recording rule 的滞后 ##########"
echo "每 1 秒采样一次，共 30 次，记录 (查询时刻, 样本时间戳, 值)"
echo

PREV_VAL=""
CHANGES=0
for i in $(seq 1 30); do
  curl -s -G "$PROM/api/v1/query" \
    --data-urlencode 'query=job:app_requests_error:ratio1m' \
    | python3 -c "
import json,sys,time
r = json.load(sys.stdin)['data']['result']
now = time.time()
if r:
    ts, v = r[0]['value']
    print('%.3f %.3f %.6f' % (now, float(ts), float(v)))
" 
  sleep 1
done > /tmp/rr_samples.txt

python3 - << 'PYEOF'
import time
rows = []
with open('/tmp/rr_samples.txt') as f:
    for line in f:
        parts = line.split()
        if len(parts) == 3:
            rows.append((float(parts[0]), float(parts[1]), float(parts[2])))

if not rows:
    print("无样本")
else:
    print("  采样次数: %d" % len(rows))
    lag = [q - s for q, s, _ in rows]
    print("  查询时刻 - 样本时间戳 的滞后: 最小=%.3fs 最大=%.3fs 平均=%.3fs"
          % (min(lag), max(lag), sum(lag)/len(lag)))
    vals = [v for _, _, v in rows]
    uniq = []
    for v in vals:
        if not uniq or abs(v - uniq[-1]) > 1e-9:
            uniq.append(v)
    print("  值的不同取值个数: %d （采样 %d 次）" % (len(uniq), len(rows)))
    print("  -> 说明 recording rule 的值在两次求值之间是'冻结'的")
    print()
    print("  逐次采样（查询时刻 / 样本时间戳 / 值）:")
    for q, s, v in rows[:12]:
        print("    %.1f  %.1f  %.6f" % (q, s, v))
    print("    ... (略)")
PYEOF
