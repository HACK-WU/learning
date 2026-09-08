set +x
PROM=http://localhost:9094

docker exec l4-app python3 -c "
import urllib.request
print(urllib.request.urlopen('http://localhost:8080/fault/wobble?center=0.08&period=24&amp=0.04').read().decode())
"

echo "错误率在 0.04~0.12 振荡；阈值：Wobble=0.05(for=0s)、Critical=0.1(for=20s)"
echo "采样 90 秒（每 3 秒一次），统计 for=0s 告警的状态翻转次数"
echo

PREV=""
FLIPS=0
for i in $(seq 1 30); do
  sleep 3
  cur=$(curl -s "$PROM/api/v1/alerts" | python3 -c "
import json,sys
d = json.load(sys.stdin)['data']['alerts']
m = {a['labels'].get('alertname'): a['state'] for a in d}
print('%s|%s' % (m.get('L4ErrorRateWobble','-'), m.get('L4HighErrorRate','-')))
")
  w=$(echo "$cur" | cut -d'|' -f1)
  c=$(echo "$cur" | cut -d'|' -f2)
  if [ -n "$PREV" ] && [ "$w" != "$PREV" ]; then
    FLIPS=$((FLIPS+1))
    echo "  t=$((i*3))s  Wobble: $PREV -> $w   <-- 翻转 #$FLIPS   (Critical=$c)"
  else
    echo "  t=$((i*3))s  Wobble=$w  Critical=$c"
  fi
  PREV="$w"
done

echo
echo "=== 90 秒内 Wobble(for=0s) 状态翻转次数: $FLIPS ==="
