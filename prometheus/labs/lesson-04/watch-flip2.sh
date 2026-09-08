set +x
PROM=http://localhost:9094

# 关键调整：
# 1) 振荡周期必须 >> rate 窗口。原 period=24s 远小于 1m 窗口，被完全抹平（实测 0.076~0.084 几乎不动）
#    改为 period=120s，让窗口只平滑一部分，仍能跨过阈值
# 2) 振幅加大到 0.06，中心 0.075 => 瞬时在 0.015~0.135 之间摆动
#    ratio1m 预计在 0.04~0.11 之间摆动，可跨过 Wobble 阈值 0.05
docker exec l4-app python3 -c "
import urllib.request
print(urllib.request.urlopen('http://localhost:8080/fault/wobble?center=0.075&period=120&amp=0.06').read().decode())
"

echo "先让新振荡跑满一个 rate 窗口（70 秒），再开始采样"
sleep 70

echo
echo "=== 采样 150 秒（每 5 秒一次），观察 for=0s 告警的翻转 ==="
PREV=""
FLIPS=0
for i in $(seq 1 30); do
  out=$(curl -s -G "$PROM/api/v1/query" \
    --data-urlencode 'query=job:app_requests_error:ratio1m' \
    | python3 -c "
import json,sys
r = json.load(sys.stdin)['data']['result']
print('%.4f' % float(r[0]['value'][1]) if r else 'n/a')
")
  st=$(curl -s "$PROM/api/v1/alerts" | python3 -c "
import json,sys
d = json.load(sys.stdin)['data']['alerts']
m = {a['labels'].get('alertname'): a['state'] for a in d}
print('%s' % m.get('L4ErrorRateWobble','-'))
")
  mark=""
  if [ -n "$PREV" ] && [ "$st" != "$PREV" ]; then
    FLIPS=$((FLIPS+1))
    mark="   <-- 翻转 #$FLIPS ($PREV -> $st)"
  fi
  echo "  t=$((i*5))s  ratio1m=$out  Wobble=$st$mark"
  PREV="$st"
  sleep 5
done

echo
echo "=== 150 秒内 Wobble(for=0s) 状态翻转次数: $FLIPS ==="
