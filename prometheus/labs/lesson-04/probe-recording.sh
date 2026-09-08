set +x
PROM=http://localhost:9094

echo "########## recording rule 的新鲜度代价 ##########"
echo "对比：直接查询 vs 查 recording rule 的结果"
echo

echo "=== 1) 同时查两个，比较时间戳与数值 ==="
echo "--- 直接算（表达式内联） ---"
curl -s -G "$PROM/api/v1/query" \
  --data-urlencode 'query=sum by (job) (rate(app_requests_total{status="500"}[1m])) / clamp_min(sum by (job) (rate(app_requests_total[1m])), 1e-9)' \
  | python3 -c "
import json,sys
r = json.load(sys.stdin)['data']['result']
for x in r:
    ts, v = x['value']
    print('  时间戳=%s  值=%.6f  job=%s' % (ts, float(v), x['metric'].get('job')))
"

echo "--- 查 recording rule 产物 ---"
curl -s -G "$PROM/api/v1/query" \
  --data-urlencode 'query=job:app_requests_error:ratio1m' \
  | python3 -c "
import json,sys
r = json.load(sys.stdin)['data']['result']
for x in r:
    ts, v = x['value']
    print('  时间戳=%s  值=%.6f  job=%s' % (ts, float(v), x['metric'].get('job')))
"

echo
echo "=== 2) 关键：recording rule 产物的时间戳 = 求值时刻，不是查询时刻 ==="
echo "连续查 8 次，每次间隔 2 秒，观察 timestamp 是否随查询时刻变化"
for i in $(seq 1 8); do
  curl -s -G "$PROM/api/v1/query" \
    --data-urlencode 'query=job:app_requests_error:ratio1m' \
    | python3 -c "
import json,sys,time
r = json.load(sys.stdin)['data']['result']
now = time.time()
if r:
    ts, v = r[0]['value']
    print('  查询时刻=%.1f  样本时间戳=%s  滞后=%.1fs  值=%.6f' % (now, ts, now-float(ts), float(v)))
"
  sleep 2
done

echo
echo "=== 3) recording rule 的求值间隔（决定新鲜度上限） ==="
curl -s -G "$PROM/api/v1/query" \
  --data-urlencode 'query=prometheus_rule_group_interval_seconds{rule_group=~".*l4-C-recording"}' \
  | python3 -c "
import json,sys
r = json.load(sys.stdin)['data']['result']
for x in r:
    print('  %s -> %s 秒' % (x['metric'].get('rule_group'), x['value'][1]))
"

echo
echo "=== 4) 验证：新指标出现后，recording rule 会不会'查不到值' ==="
echo "（模拟：查一个刚创建、还没到下一次求值的 recording rule）"
curl -s -G "$PROM/api/v1/query" \
  --data-urlencode 'query=job:app_requests:rate1m' \
  | python3 -c "
import json,sys
r = json.load(sys.stdin)['data']['result']
print('  返回 %d 条' % len(r))
for x in r:
    print('    %s = %s' % (x['metric'].get('job'), x['value'][1]))
"
