set +x
PROM=http://localhost:9094

echo "########## 恢复延迟：为什么关掉故障后告警还亮着 ##########"
echo "已注入 /fault/off，继续观察直到告警消失"
echo "重点：rate()[1m] 的窗口需要 60 秒才能把故障期数据完全滑出"
echo

START=$(date +%s)
PREV_W=""; PREV_C=""
for i in $(seq 1 30); do
  out=$(curl -s "$PROM/api/v1/alerts" | python3 -c "
import json,sys
d = json.load(sys.stdin)['data']['alerts']
m = {a['labels'].get('alertname'): a['state'] for a in d}
print('%s|%s' % (m.get('L4ErrorRateWobble','-'), m.get('L4HighErrorRate','-')))
")
  val=$(curl -s -G "$PROM/api/v1/query" \
    --data-urlencode 'query=job:app_requests_error:ratio1m' \
    | python3 -c "
import json,sys
r = json.load(sys.stdin)['data']['result']
print('%.4f' % float(r[0]['value'][1]) if r else 'n/a')
")
  w=$(echo "$out" | cut -d'|' -f1)
  c=$(echo "$out" | cut -d'|' -f2)
  now=$(date +%s)
  elapsed=$((now - START))
  mark=""
  [ -n "$PREV_C" ] && [ "$c" != "$PREV_C" ] && mark="  <== Critical: $PREV_C -> $c"
  [ -n "$PREV_W" ] && [ "$w" != "$PREV_W" ] && mark="$mark  |  Wobble: $PREV_W -> $w"
  echo "  t=${elapsed}s  ratio1m=$val  Wobble=$w  Critical=$c$mark"
  PREV_W="$w"; PREV_C="$c"
  if [ "$w" = "-" ] && [ "$c" = "-" ]; then
    echo
    echo "  === 两条告警均已消失，总耗时约 ${elapsed} 秒 ==="
    break
  fi
  sleep 5
done
