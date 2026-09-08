set +x
PROM=http://localhost:9094

echo "########## keep_firing_for 完整观察（延长到 120 秒） ##########"

docker exec l4-app python3 -c "
import urllib.request
print(urllib.request.urlopen('http://localhost:8080/fault/on?rate=0.5').read().decode())
" > /dev/null
sleep 25

echo "=== 故障中，两条都应为 firing ==="
curl -s "$PROM/api/v1/alerts" | python3 -c "
import json,sys
d = json.load(sys.stdin)['data']['alerts']
for a in d:
    print('  %-24s %s' % (a['labels'].get('alertname'), a['state']))
"

echo
docker exec l4-app python3 -c "
import urllib.request
urllib.request.urlopen('http://localhost:8080/fault/off').read()
" > /dev/null
echo "=== 已关掉故障，开始计时 ==="

START=$(date +%s)
GONE_W=""; GONE_K=""
for i in $(seq 1 30); do
  out=$(curl -s "$PROM/api/v1/alerts" | python3 -c "
import json,sys
d = json.load(sys.stdin)['data']['alerts']
m = {a['labels'].get('alertname'): a['state'] for a in d}
print('%s|%s' % (m.get('L4ErrorRateWobble','-'), m.get('L4ErrorRateKeepFiring','-')))
")
  w=$(echo "$out" | cut -d'|' -f1)
  k=$(echo "$out" | cut -d'|' -f2)
  now=$(date +%s); el=$((now-START))
  [ -z "$GONE_W" ] && [ "$w" = "-" ] && GONE_W=$el && echo "  t=${el}s  Wobble 消失（无 keep_firing_for）"
  [ -z "$GONE_K" ] && [ "$k" = "-" ] && GONE_K=$el && echo "  t=${el}s  KeepFiring 消失（keep_firing_for=30s）"
  if [ -n "$GONE_W" ] && [ -n "$GONE_K" ]; then
    echo
    echo "  === 对比结果 ==="
    echo "    Wobble(for=0s, 无 keep_firing_for)   : ${GONE_W}s 后消失"
    echo "    KeepFiring(keep_firing_for=30s)      : ${GONE_K}s 后消失"
    echo "    多存活: $((GONE_K - GONE_W)) 秒"
    break
  fi
  sleep 4
done
